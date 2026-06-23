#include <Wire.h>

#define SERIAL_BAUND 9600
#define MAX_BPM 180
#define MIN_BPM 30

int currentBPM = 0;
int tickCount = 0;
bool playing = false;

unsigned long waitStart = 0;
unsigned long waitMs = 0;
bool waiting = false;
bool finishWaiting = false;

void setup() {
  Serial.begin(SERIAL_BAUND);
  Wire.begin();
  Serial.println("Master Arduino Ready");
}

void loop() {

  // Processingからシリアルデータが届いているか確認
  if (Serial.available() > 0) {

    String input = Serial.readStringUntil('\n');
    input.trim();

    // パターンA：初期設定データ（8桁）が届いた場合
    if (input.length() == 8) {

      String bpmStr = input.substring(5, 8);
      currentBPM = bpmStr.toInt();

      if (currentBPM >= MIN_BPM && currentBPM <= MAX_BPM) {
        // I2Cを使って、全Slaveへ8桁の文字列をそのまま一斉送信
        Wire.beginTransmission(0);
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
        
        // 小数の切り捨てを防ぐため、先に30000を掛け算する
        waitMs = 30000UL / (unsigned long)currentBPM; 
        waitStart = millis();
      }
    }

    // パターンB：演奏中のBPM同期データ（3桁）が届いた場合
    else if (input.length() == 3) {
      int newBPM = input.toInt();
      if (newBPM >= MIN_BPM && newBPM <= MAX_BPM) {
        
        // ★【ここを修正】演奏中かつ通常待機中の場合、タイマーの「残り時間」を計算し直す
        if (playing && waiting && !finishWaiting) {
          unsigned long elapsed = millis() - waitStart; // 現在のTickが始まってからの経過時間
          
          // 古いBPMでの進捗率（パーセンテージ）を計算
          double progress = (double)elapsed / (double)waitMs;
          if (progress > 1.0) progress = 1.0; // 100%を超えないようガード
          
          // BPMの値を更新
          currentBPM = newBPM;
          
          // 新しいBPM基準での「1Tickの合計時間」を再計算
          waitMs = 30000UL / (unsigned long)currentBPM;
          
          // 進捗率に合わせて、新しいwaitStart（仮想的な開始時間）を逆算して補正
          // これにより「現在のTickの残りの長さ」が新しいBPMのテンポに伸縮します
          waitStart = millis() - (unsigned long)((double)waitMs * progress);
          
        } else {
          // 演奏前、または最終待機中の場合は単にBPMの値を更新
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

  // 通常待機タイマー（30 / BPM * 1000 ms 分きっちり待つ処理）
  if (playing && waiting && !finishWaiting) {
    if (millis() - waitStart >= waitMs) {
      // 待機時間が経過したので、一旦フラグをクリア
      waiting = false; 

      if (tickCount >= 98) {
        // 98回目の待機が完了 ➔ 最終待機へ移行
        finishWaiting = true;
        
        // 30000を先にする計算式に修正
        waitMs = (30000UL / (unsigned long)currentBPM) + 500UL;
        waitStart = millis();
        Serial.print("[Finish Wait] ");
        Serial.print(waitMs);
        Serial.println(" ms");

      } else {
        // まだ 98回に達していない場合：次のBPM（Tick）を送信
        tickCount++;
        char sendBpmStr[4];
        sprintf(sendBpmStr, "%03d", currentBPM);
        
        Wire.beginTransmission(0);
        Wire.print(sendBpmStr);
        Wire.endTransmission();
        
        // Processing側がカウント（BEAT）として検知するためのログ
        Serial.print("[BPM Tick] Sent: ");
        Serial.print(sendBpmStr);
        Serial.print("  tick: ");
        Serial.println(tickCount);

        // 次の送信までの待機タイマーをここでもう一度ONにする
        waiting = true; 
        waitMs = 30000UL / (unsigned long)currentBPM;
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