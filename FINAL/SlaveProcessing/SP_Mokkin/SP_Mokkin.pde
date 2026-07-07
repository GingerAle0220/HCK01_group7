// ============================================================
// Slave_mokkin_Processing.pde - 木琴（Marimba）スレーブ Processing
// Slave ArduinoからSerial受信 → 木琴音色で再生（Minim使用）
// ============================================================

import ddf.minim.*;
import ddf.minim.ugens.*;

Minim minim;
AudioOutput out;

// ------------------------------------------------------------
// 木琴音色クラス（piano_ptype4.pdeから移植・木琴音色に変更）
// ------------------------------------------------------------
class Marimba implements Instrument {
  Oscil  osc1, osc2, osc3, osc4;
  Summer summer;
  ADSR   adsr;

  Marimba(float frequency, float amplitude) {
    osc1 = new Oscil(frequency * 1.0f, 0.50f, Waves.SINE);
    osc2 = new Oscil(frequency * 2.0f, 0.10f, Waves.SINE);
    osc3 = new Oscil(frequency * 3.0f, 0.10f, Waves.SINE);
    osc4 = new Oscil(frequency * 4.0f, 0.35f, Waves.SINE);

    summer = new Summer();
    osc1.patch(summer);
    osc2.patch(summer);
    osc3.patch(summer);
    osc4.patch(summer);

    adsr = new ADSR(amplitude, 0.001, 0.15, 0.0, 0.01);
    summer.patch(adsr);
  }

  void noteOn(float duration) {
    adsr.noteOn();
    adsr.patch(out);
  }

  void noteOff() {
    adsr.noteOff();
    adsr.unpatchAfterRelease(out);
  }
}

// ------------------------------------------------------------
// Serial
// ------------------------------------------------------------
import processing.serial.*;
Serial slavePort;

// ------------------------------------------------------------
void setup() {
  size(400, 200);
  minim = new Minim(this);
  out   = minim.getLineOut();

  printArray(Serial.list());
  // ★ ポート番号を環境に合わせて変更
  slavePort = new Serial(this, Serial.list()[4], 9600);
  slavePort.bufferUntil('\n');

  println("SlaveProcessing（木琴）起動");
}

void draw() {
  background(0);
  stroke(255);
  for (int i = 0; i < out.bufferSize() - 1; i++) {
    line(i, 50  - out.left.get(i)  * 50, i+1, 50  - out.left.get(i+1)  * 50);
    line(i, 150 - out.right.get(i) * 50, i+1, 150 - out.right.get(i+1) * 50);
  }
  fill(255);
  textSize(14);
  text("木琴受信待機中...", 20, 185);
}

// ------------------------------------------------------------
// Slave ArduinoからSerial受信
// フォーマット："pitch,duration\n"（pitchはMIDIノート番号）
// ------------------------------------------------------------
void serialEvent(Serial p) {
  String line = trim(p.readStringUntil('\n'));
  if (line == null) return;

  // ステータスメッセージはスキップ
  if (line.equals("START") || line.equals("END") || line.equals("Slave ready")) {
    println("[Slave] " + line);
    return;
  }

  String[] parts = split(line, ',');
  if (parts.length < 2) return;

  int midiNote = int(parts[0]);
  float durSec = int(parts[1]) / 1000.0;  // ms → 秒

  // MIDIノート番号 → 周波数
  float freq = 440.0 * pow(2.0, (midiNote - 69) / 12.0);

  // 木琴音色で再生
  out.playNote(0.0, durSec, new Marimba(freq, 0.6));

  println("再生 midi:" + midiNote + " freq:" + nf(freq, 0, 1) + "Hz dur:" + durSec + "s");
}

void stop() {
  minim.stop();
  super.stop();
}
