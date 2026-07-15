// ============================================================
// CanonTestSALogger.pde - T1+T2用 SA単ポートロガー（SA1台につきPC1台の分散構成用）
//
// 担当のSlave Arduino（SlaveArduinoCanonTest.inoをフラッシュ済み）1台の
// シリアルポートだけを開き，SAが自己申告する設定確認行（"CFG,..."）と
// 毎Tickログ行（"C,..."）をCSVファイルへ記録する。
//
// 判定に使う値（tick_id・楽譜添字・音符イベント・pickup_us）はすべて
// Arduino側の自己計測・自己申告値なので，PC間の時刻合わせは不要。
// このPCが付けるタイムスタンプ（pc_recv_time_us）は参考値でしかない。
//
// 【操作は基本的に不要（全自動）】
//   - CFG行の受信（=Master担当がSPACEで演奏開始）でログファイルを自動作成。
//     ファイル名の楽器名はCFG行のINST_IDから，BPMもCFG行から自動決定される。
//     例: canon_log_flute_bpm120_run1.csv / canon_log_config_flute_bpm120_run1.csv
//   - 演奏終了後，5秒間受信がなければ自動でログを閉じ，run番号を+1して待機に戻る。
//     run番号はCFG受信（=演奏開始）のたびに全PCで同じように進むため，
//     全PCを最初のrunの前に起動しておけば番号は揃う。
//   - [s]キーで手動クローズもできる（自動クローズを待たない場合）。
//
// 【事前設定】下の SA_PORT_NAME を設定する。空文字のままなら
// "usbmodem" を含む最初のポートを自動選択する（macOS想定。Windowsは
// "COM3" 等を明示的に設定すること）。
// ============================================================

import processing.serial.*;
import java.time.Instant;

// ★ 担当SAのポート名。空文字なら自動選択（コンソールに候補一覧が出る）
String SA_PORT_NAME = "";

static final int CLOSE_TIMEOUT_MS = 5000;  // この時間受信が途切れたらrun終了とみなす

String[] INST_NAMES = {"?", "piano", "mokkin", "flute", "drum"};

Serial saPort;
PrintWriter saLog;    // 毎Tickログ
PrintWriter cfgLog;   // 設定確認ログ（このSAの分だけ。分析時に4台分を自動マージ）

int runNo = 1;
int instId = -1;          // CFG行から自動判別
String instName = "?";
String currentSuffix = "";
int tickLines = 0;        // 受信したC行の数（207件が期待値）
int lastTickId = -1;
long lastLineMs = 0;
boolean logging = false;

void setup() {
  size(560, 260);
  printArray(Serial.list());
  PFont font = createFont("Meiryo", 50);
  textFont(font);

  String portName = Serial.list()[2];
  if (portName == null) {
    println("シリアルポートが見つかりません。");
    exit();
    return;
  }
  saPort = new Serial(this, portName, 115200);
  saPort.bufferUntil('\n');
  println("CanonTestSALogger 起動。ポート: " + portName + "（CFG受信で自動的にログ開始）");
}

String pickPort() {
  if (SA_PORT_NAME.length() > 0) return SA_PORT_NAME;
  String[] ports = Serial.list();
  for (String p : ports) {
    if (p.contains("usbmodem")) return p;  // macOSのArduinoポート
  }
  return (ports.length > 0) ? ports[ports.length - 1] : null;
}

void draw() {
  // 演奏終了の自動検知（最後のTickからCLOSE_TIMEOUT_MS無受信でクローズ）
  if (logging && tickLines > 0 && millis() - lastLineMs > CLOSE_TIMEOUT_MS) {
    println("受信が" + (CLOSE_TIMEOUT_MS / 1000) + "秒途切れたため run " + runNo + " を自動終了します。");
    closeLogs();
  }

  background(20);
  fill(255);
  textSize(18);
  text("輪唱テスト SAロガー（1PC=1SA構成）", 20, 32);
  textSize(14);
  text("楽器: " + instName + (instId > 0 ? " (INST_ID=" + instId + ")" : "（CFG受信で自動判別）"), 20, 64);
  text("run: " + runNo + "   状態: " + (logging ? "記録中" : "待機中（Master側の開始を待っています）"), 20, 88);
  text("受信Tick数: " + tickLines + (logging ? "" : "（前回run）") + "   最終tick_id: " + lastTickId, 20, 112);
  text("期待値: 207 Tick（tick_id 2〜208）", 20, 136);
  text("[s] 手動でログを閉じる（通常は自動クローズ）", 20, 176);
}

void keyPressed() {
  if (key == 's' && logging) {
    println("手動クローズ: run " + runNo);
    closeLogs();
  }
}

void serialEvent(Serial p) {
  String line = p.readStringUntil('\n');
  if (line == null) return;
  line = trim(line);

  // 設定確認行 "CFG,<inst>,<octave>,<order>,<bpm>,<startTick>" = 演奏開始の合図
  if (line.startsWith("CFG,")) {
    if (logging) {
      // 前のrunが自動クローズされる前に次が始まった場合の保険
      println("前のrunが開いたまま次のCFGを受信。先に閉じます。");
      closeLogs();
    }
    String[] f = split(line, ',');
    if (f.length >= 6) {
      instId = int(f[1]);
      instName = (instId >= 1 && instId <= 4) ? INST_NAMES[instId] : "unknown";
      int bpm = int(f[4]);
      openLogs(bpm);
      cfgLog.println(nowMicros() + "," + line.substring(4));
      cfgLog.flush();
      println("[" + instName + "] CFG受信 → 記録開始 " + line);
    }
    return;
  }

  // 毎Tickログ行 "C,<inst>,<tick>,..." → 到着時刻を先頭に付けてそのまま記録
  if (line.startsWith("C,")) {
    if (!logging) {
      println("警告: ログ未開始でC行を受信（演奏途中からの起動？）。この行は捨てます: " + line);
      return;
    }
    saLog.println(nowMicros() + "," + line.substring(2));
    saLog.flush();
    tickLines++;
    String[] f = split(line, ',');
    if (f.length >= 3) lastTickId = int(f[2]);
    lastLineMs = millis();
    return;
  }

  println("[SA] " + line);
}

void openLogs(int bpm) {
  currentSuffix = "_bpm" + bpm + "_run" + runNo;

  saLog = createWriter("canon_log_" + instName + currentSuffix + ".csv");
  saLog.println("pc_recv_time_us,inst_id,tick_id,score_index,"
                + "to1,to2,to3,dur_to,he1,he2,he3,dur_he,pickup_us");

  cfgLog = createWriter("canon_log_config_" + instName + currentSuffix + ".csv");
  cfgLog.println("pc_recv_time_us,inst_id,octave,order,bpm,start_tick");

  tickLines = 0;
  lastTickId = -1;
  lastLineMs = millis();
  logging = true;
  println("ログ作成: canon_log_" + instName + currentSuffix + ".csv");
}

void closeLogs() {
  if (saLog != null)  { saLog.flush();  saLog.close();  saLog = null; }
  if (cfgLog != null) { cfgLog.flush(); cfgLog.close(); cfgLog = null; }
  logging = false;
  println("run " + runNo + " 終了。受信Tick数: " + tickLines + "（期待値207）");
  runNo++;
}

long nowMicros() {
  Instant t = Instant.now();
  return t.getEpochSecond() * 1_000_000L + t.getNano() / 1000;
}

void stop() {
  closeLogs();
  super.stop();
}
