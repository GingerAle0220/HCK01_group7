// ============================================================
// SlaveProcessing.pde - プロトタイプ（PC1 / ピアノ用）
// Slave ArduinoからSerial受信 → ピアノ音色で再生（Minim使用）
// ============================================================

import ddf.minim.*;
import ddf.minim.ugens.*;

Minim minim;
AudioOutput out;

// ------------------------------------------------------------
// ピアノ音色クラス（piano_ptype4.pdeから移植）
// ------------------------------------------------------------
class Piano implements Instrument {
  Oscil wave;
  ADSR adsr;
  Waveform pianoWave;
  MoogFilter filter;
  Line filterEnv;

  Piano(float frequency, float amplitude) {
    float B = 0.0004;
    float[] multipliers = new float[6];
    for (int n = 1; n <= 6; n++) {
      multipliers[n-1] = n * sqrt(1 + B * n * n);
    }
    float[] amplitudes = { 1.0, 0.75, 0.6, 0.58, 0.67, 0.38 };
    float[] phases     = { 0.0, 0.52, 2.62, 4.19, 1.05, 5.24 };

    pianoWave = WavetableGenerator.gen9(4096, multipliers, amplitudes, phases);
    wave = new Oscil(frequency, amplitude, pianoWave);
    adsr = new ADSR(0.8, 0.01, 0.1, 0.5, 0.2);

    float maxCutoff = min(10000, frequency * 5);
    float minCutoff = frequency * 1.1;
    filterEnv = new Line(0.8, maxCutoff, minCutoff);
    filter = new MoogFilter(maxCutoff, 0.1, MoogFilter.Type.LP);

    wave.patch(filter);
    filter.patch(adsr);
    filterEnv.patch(filter.frequency);
  }

  void noteOn(float duration) {
    adsr.noteOn();
    filterEnv.activate();
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

  println("SlaveProcessing（ピアノ）起動");
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
  text("ピアノ受信待機中...", 20, 185);
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

  // ピアノ音色で再生
  out.playNote(0.0, durSec, new Piano(freq, 0.6));

  println("再生 midi:" + midiNote + " freq:" + nf(freq, 0, 1) + "Hz dur:" + durSec + "s");
}

void stop() {
  minim.stop();
  super.stop();
}
