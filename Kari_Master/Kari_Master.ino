// Kari_Master.ino
// UI.pde とシリアル通信で接続し，初回 8 バイトパケット受信・BPM 更新受信・START/FINISH 送信を確認するためのテスト用スケッチ

int octave = 0;          // 国際式オクターブ (-1〜9)
int playOrder[3] = {0, 0, 0};
int bpm = 120;

bool hasInitialPacket = false;
bool hasSentStart = false;
bool hasSentFinish = false;
unsigned long packetReceivedAt = 0;

void setup() {
  Serial.begin(9600);
  while (!Serial) {
    ; // シリアル接続待ち
  }

  Serial.println("Kari_Master test ready");
  Serial.println("Waiting for initial 8-byte packet from Processing...");
}

void loop() {
  readSerialLine();

  if (hasInitialPacket && !hasSentStart && millis() - packetReceivedAt >= 1000UL) {
    sendStartMessage();
  }

  if (hasSentStart && !hasSentFinish && millis() - packetReceivedAt >= 15000UL) {
    sendFinishMessage();
  }
}

void readSerialLine() {
  static String line = "";

  while (Serial.available() > 0) {
    char c = Serial.read();
    if (c == '\r') {
      continue;
    }
    if (c == '\n') {
      if (line.length() > 0) {
        processIncomingLine(line);
        line = "";
      }
    } else {
      line += c;
    }
  }
}

void processIncomingLine(const String &line) {
  if (line.length() == 8) {
    parseInitialPacket(line);
  } else if (line.length() == 3) {
    parseBpmPacket(line);
  } else {
    Serial.print("UNKNOWN_PACKET len=");
    Serial.println(line.length());
    Serial.print("  data=");
    Serial.println(line);
  }
}

void parseInitialPacket(const String &line) {
  String octStr = line.substring(0, 2);
  String orderStr = line.substring(2, 5);
  String bpmStr = line.substring(5, 8);

  int octValue = octStr.toInt();
  octave = octValue - 1; // 送信値 00→-1, 01→0, ..., 10→9
  for (int i = 0; i < 3; i++) {
    playOrder[i] = orderStr.charAt(i) - '0';
  }
  bpm = bpmStr.toInt();

  hasInitialPacket = true;
  hasSentStart = false;
  hasSentFinish = false;
  packetReceivedAt = millis();

  Serial.println("INITIAL_PACKET_OK");
  Serial.print("  octave="); Serial.println(octave);
  Serial.print("  playOrder=");
  for (int i = 0; i < 3; i++) {
    Serial.print(playOrder[i]);
    if (i < 2) Serial.print(",");
  }
  Serial.println();
  Serial.print("  bpm="); Serial.println(bpm);
  Serial.println("Will send START after 1 second, FINISH after 6 seconds.");
}

void parseBpmPacket(const String &line) {
  if (!hasInitialPacket) {
    Serial.println("BPM_UPDATE_IGNORED: initial packet not received yet");
    return;
  }
  int newBpm = line.toInt();
  bpm = newBpm;
  Serial.print("BPM_UPDATE_OK: ");
  Serial.println(bpm);
}

void sendStartMessage() {
  Serial.println("START");
  hasSentStart = true;
  Serial.println("SENT_START");
}

void sendFinishMessage() {
  Serial.println("FINISH");
  hasSentFinish = true;
  Serial.println("SENT_FINISH");
}
