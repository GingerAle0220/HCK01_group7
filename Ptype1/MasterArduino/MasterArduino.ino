// ============================================================
// MA_ptype2.ino - Master Arduino（演奏制御の親機）
// Processingから初期設定（8桁）とBPM同期（3桁）をSerialで受信し，
// I2Cで全Slaveへブロードキャストしながら全208Tick分のテンポを管理する。
// ============================================================

#include <Wire.h>

// ------------------------------------------------------------
// 定数定義
// ------------------------------------------------------------
#define SERIAL_BAUND 115200
#define MAX_BPM 180
#define MIN_BPM 30

// 全Slave共通のI2Cアドレス（擬似ブロードキャスト用）。
// アドレス0（General Call）はWireライブラリ標準APIでは有効化できず，
// Uno R4ではNACK時に約1秒の遅延が発生するため使用しない。
#define SLAVE_BROADCAST_ADDRESS 0

// ------------------------------------------------------------
// グローバル変数
// ------------------------------------------------------------
int currentBPM = 0;      // 現在のBPM（30〜180）
int tickCount = 0;       // 送信済みTick数（1〜208）
bool playing = false;    // 演奏中フラグ

unsigned long waitStart = 0;      // 現在の待機タイマーの開始時刻（millis）
unsigned long waitMs = 0;         // 現在の待機タイマーの長さ（ms）
bool waiting = false;             // 通常待機タイマー作動中フラグ
bool finishWaiting = false;       // 最終待機（音の消音待ち）フラグ

// Serial受信用バッファ（ブロッキングするreadStringUntilは使わない）
char rxBuf[16];
int rxLen = 0;

void setup() {
  Serial.begin(SERIAL_BAUND);
  Wire.begin();
  Serial.println("Master Arduino Ready");
}

// ------------------------------------------------------------
// Processingからの受信データを解析し，演奏開始やBPM更新を行う
// ------------------------------------------------------------
void handleInput(const String &rawInput) {
  String input = rawInput;
  input.trim();

  // パターンA：初期設定データ（8桁）が届いた場合
  if (input.length() == 8) {

    String bpmStr = input.substring(5, 8);
    currentBPM = bpmStr.toInt();

    if (currentBPM >= MIN_BPM && currentBPM <= MAX_BPM) {
      // I2Cを使って，全Slaveへ8桁の文字列をそのまま一斉送信
      Wire.beginTransmission(SLAVE_BROADCAST_ADDRESS);
      Wire.print(input);
      Wire.endTransmission();

      // Processing画面制御用のトリガーログ
      Serial.println("START");
      Serial.println("Config Fowarded");

      // 演奏開始：初期パケットを送信した時点を「1回目のTick」とする
      tickCount = 1;
      playing = true;
      waiting = true;          // タイマー作動開始
      finishWaiting = false;

      // 小数の切り捨てを防ぐため，先に15000を掛け算する
      waitMs = 15000UL / (unsigned long)currentBPM;
      waitStart = millis();
    }
  }

  // パターンB：演奏中のBPM同期データ（3桁）が届いた場合
  else if (input.length() == 3) {
    int newBPM = input.toInt();
    if (newBPM >= MIN_BPM && newBPM <= MAX_BPM) {

      // 演奏中かつ通常待機中の場合，タイマーの「残り時間」を新しいBPMに合わせて再計算する
      if (playing && waiting && !finishWaiting) {
        unsigned long elapsed = millis() - waitStart; // 現在のTickが始まってからの経過時間

        // 古いBPMでの進捗率（パーセンテージ）を計算
        double progress = (double)elapsed / (double)waitMs;
        if (progress > 1.0) progress = 1.0; // 100%を超えないようガード

        // BPMの値を更新
        currentBPM = newBPM;

        // 新しいBPM基準での「1Tickの合計時間」を再計算
        waitMs = 15000UL / (unsigned long)currentBPM;

        // 進捗率に合わせて，新しいwaitStart（仮想的な開始時間）を逆算して補正
        // これにより「現在のTickの残りの長さ」が新しいBPMのテンポに伸縮します
        waitStart = millis() - (unsigned long)((double)waitMs * progress);

      } else {
        // 演奏前，または最終待機中の場合は単にBPMの値を更新
        currentBPM = newBPM;
      }

      Serial.print("[BPM Sync] Updated currentBPM: ");
      Serial.println(currentBPM);
    }
  }

  // エラー対策
  else {
    Serial.print("[Warning] Invalid data length: ");
    Serial.println(input);
  }
}

// ------------------------------------------------------------
// メインループ（Serial受信処理 ＋ Tick送信タイマー）
// ------------------------------------------------------------
void loop() {

  // Processingからのシリアルデータを，ブロッキングせずに1バイトずつ読み進める。
  // readStringUntil()は改行が来るまで最大1000ms待ってしまい，ノイズ等で
  // 不完全なバイトが混入するとTick送信タイマー全体が止まってしまうため使わない。
  while (Serial.available() > 0) {
    char c = Serial.read();
    if (c == '\n') {
      rxBuf[rxLen] = '\0';
      handleInput(String(rxBuf));
      rxLen = 0;
    } else if (c != '\r' && rxLen < (int)sizeof(rxBuf) - 1) {
      rxBuf[rxLen++] = c;
    }
  }

  // 通常待機タイマー（30 / BPM * 1000 ms 分きっちり待つ処理）
  if (playing && waiting && !finishWaiting) {
    if (millis() - waitStart >= waitMs) {
      // 待機時間が経過したので，一旦フラグをクリア
      waiting = false; 

      if (tickCount >= 208) {
        // 208回目の待機が完了 ➔ 最終待機へ移行
        finishWaiting = true;

        // 小数の切り捨てを防ぐため，先に15000を掛け算してから割る
        waitMs = (15000UL / (unsigned long)currentBPM) + 500UL;
        waitStart = millis();
        Serial.print("[Finish Wait] ");
        Serial.print(waitMs);
        Serial.println(" ms");

      } else {
        // まだ 208回に達していない場合：次のBPM（Tick）を送信
        tickCount++;
        char sendBpmStr[4];
        sprintf(sendBpmStr, "%03d", currentBPM);
        
        Wire.beginTransmission(SLAVE_BROADCAST_ADDRESS);
        Wire.print(sendBpmStr);
        Wire.endTransmission();
        
        // Processing側がカウント（BEAT）として検知するためのログ
        Serial.print("[BPM Tick] Sent: ");
        Serial.print(sendBpmStr);
        Serial.print("  tick: ");
        Serial.println(tickCount);

        // 次の送信までの待機タイマーをここでもう一度ONにする
        waiting = true;
        waitMs = 15000UL / (unsigned long)currentBPM;
        waitStart = millis();
      }
    }
  }

  // 最終待機タイマー（最後の音が消えるのを待つための猶予時間）
  if (playing && finishWaiting) {
    if (millis() - waitStart >= waitMs) {
      Serial.println("FINISH");
      playing = false;
      finishWaiting = false;
    }
  }
}