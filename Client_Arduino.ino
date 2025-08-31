#include <WiFiS3.h>
#include "Arduino_LED_Matrix.h"

const char* WIFI_SSID = "<your wifi name here>";
const char* WIFI_PASSWORD = "<your wifi password here>";

IPAddress PC_IP(192,168,1,128); // Your computer's ip address
const uint16_t PC_PORT = 8000; // Your server port

ArduinoLEDMatrix matrix;

// --------- 12x8 number drawing (3x5 font) ----------
static uint8_t frame[8][12];
static const uint8_t DIGITS[11][5] = {
  {0b111,0b101,0b101,0b101,0b111},{0b010,0b110,0b010,0b010,0b111},
  {0b111,0b001,0b111,0b100,0b111},{0b111,0b001,0b111,0b001,0b111},
  {0b101,0b101,0b111,0b001,0b001},{0b111,0b100,0b111,0b001,0b111},
  {0b111,0b100,0b111,0b101,0b111},{0b111,0b001,0b010,0b010,0b010},
  {0b111,0b101,0b111,0b101,0b111},{0b111,0b101,0b111,0b001,0b111},
  {0b000,0b000,0b111,0b000,0b000}
};

static inline void clearFrame(){ memset(frame,0,sizeof(frame)); }
static inline void drawGlyph(uint8_t idx,uint8_t x,uint8_t y){
  if (idx>10) return;
  for(uint8_t r=0;r<5;r++){
    uint8_t bits=DIGITS[idx][r];
    for(uint8_t c=0;c<3;c++){
      uint8_t px=x+c, py=y+r;
      if (px<12 && py<8) frame[py][px]=(bits>>(2-c))&1;
    }
  }
}
void showNumber(int v){
  char s[12]; snprintf(s,sizeof(s),"%d",v);
  uint8_t len=strlen(s); if(!len) return;
  uint8_t total=len*3+(len-1);
  int8_t x0=(12-total)/2; if(x0<0) x0=0;
  const uint8_t y0=(8-5)/2;
  clearFrame();
  uint8_t x=x0;
  for(uint8_t i=0;i<len;i++){
    uint8_t gi = (s[i]=='-')?10: (s[i]>='0'&&s[i]<='9' ? (uint8_t)(s[i]-'0') : 255);
    if (gi!=255){ drawGlyph(gi,x,y0); x+=3; if(i+1<len) x+=1; if(x>=12) break; }
  }
  matrix.renderBitmap(frame,8,12);
}

// --------- TCP + parsing ----------
WiFiClient client;
unsigned long lastConnTry=0, lastHeartbeat=0, lastRx=0;

// stream buffer
static char sbuf[512];
static size_t slen=0;

// parse an integer from sbuf; removes consumed bytes
bool extractNextInteger(long &out){
  size_t i=0;
  while(i<slen){
    if (sbuf[i]=='+'||sbuf[i]=='-') { if (i+1<slen && isdigit((unsigned char)sbuf[i+1])) break; }
    if (isdigit((unsigned char)sbuf[i])) break;
    i++;
  }
  if (i>=slen){ slen=0; return false; }
  size_t start=i;
  if (sbuf[i]=='+'||sbuf[i]=='-'){
    i++;
    if (i>=slen){ memmove(sbuf, sbuf+start, slen-start); slen -= start; return false; }
    if (!isdigit((unsigned char)sbuf[i])) { i++; start=i; }
  }
  while(i<slen && isdigit((unsigned char)sbuf[i])) i++;
  if (i==slen){ memmove(sbuf, sbuf+start, slen-start); slen -= start; return false; }
  char saved=sbuf[i]; sbuf[i]='\0';
  out = strtol(sbuf+start, nullptr, 10);
  sbuf[i]=saved;
  size_t rem = slen - i; memmove(sbuf, sbuf+i, rem); slen = rem;
  return true;
}

void showWifiAnimation() {
  matrix.loadSequence(LEDMATRIX_ANIMATION_WIFI_SEARCH);
  matrix.play(true);
}

void ensureWiFi(){
  if (WiFi.status()==WL_CONNECTED) return;
  showWifiAnimation();
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  unsigned long t0=millis();
  while(WiFi.status()!=WL_CONNECTED){
    if (millis()-t0>20000){ t0=millis(); WiFi.begin(WIFI_SSID, WIFI_PASSWORD); }
    delay(250);
  }
}

void openTCP(){
  // ensure fresh socket object
  client.stop();
  client = WiFiClient();
  if (client.connect(PC_IP, PC_PORT)) {

    slen=0;
    lastRx = millis();
    // send one short banner if it won't block (safe but optional)
    if (client.availableForWrite() >= 6) client.write((const uint8_t*)"READY\n", 6);
  }
  lastConnTry = millis();
}

void ensureTCP(){
  if (client.connected()) return;
  if (millis()-lastConnTry < 1000) return;
  showWifiAnimation();
  openTCP();
}

void pumpTCP(){
  if (!client.connected()) return;

  // 1) READ (non-blocking, drain fast)
  int avail = client.available();
  while (avail > 0) {
    uint8_t tmp[256];
    int toRead = avail > (int)sizeof(tmp) ? (int)sizeof(tmp) : avail;
    int n = client.read(tmp, toRead);
    if (n <= 0) break;
    lastRx = millis();

    // append into stream buffer, drop oldest if needed
    if (slen + (size_t)n >= sizeof(sbuf)){
      size_t drop = (slen + (size_t)n) - (sizeof(sbuf)-1);
      if (drop > slen) drop = slen;
      memmove(sbuf, sbuf+drop, slen-drop);
      slen -= drop;
    }
    memcpy(sbuf+slen, tmp, (size_t)n);
    slen += (size_t)n;

    avail = client.available(); // refresh
  }

  // 2) PARSE
  long v;
  while (extractNextInteger(v)){
    showNumber((int)v);
  }

  // 3) STALL WATCHDOG: no bytes for N seconds => hard reconnect
  const unsigned long STALL_MS = 10000; // 10 s
  if (millis() - lastRx > STALL_MS) {
    client.stop(); // ensureTCP() will re-open next loop
  }
}

void setup(){
  Serial.begin(115200);
  while(!Serial){}
  matrix.begin();
}

void loop(){
  ensureWiFi();
  ensureTCP();
  pumpTCP();

  if (millis()-lastHeartbeat > 1000){
    lastHeartbeat = millis();
  }

  // IMPORTANT for WiFiS3: yield a tiny slice each loop
  delay(1);
}
