**1\) Mimari figürlerin hazırlanması**  
Rapor içinde yer alan Mermaid diyagramları içerik olarak faydalı. Ancak makale için doğrudan yeterli değil. Bu nedenle bu diyagramların yeniden çizilip yayın kalitesinde figür haline getirilmesini istiyorum.

Hazırlanacak figürler:

* SoC genel blok diyagramı

* Pipeline iç yapısı

* AXI4-Lite interconnect / topoloji diyagramı

* DQN accelerator iç mimarisi

* DQN FSM diyagramı

Beklenen format:

* SVG, PDF veya yüksek çözünürlüklü PNG

* beyaz arka plan

* kutular hizalı ve okunaklı

* metinler sade ve temiz

* Mermaid ekran görüntüsü değil, yeniden çizilmiş figür

**2\) Test ve doğrulama çıktılarının hazırlanması**  
Aşağıdaki testlerin PASS çıktıları gerekiyor:

* tb\_rv\_all

* tb\_soc\_integration

* tb\_dqn

* tb\_dqn\_core\_standalone

* varsa tb\_dqn\_performance

Beklenenler:

* her test için ekran görüntüsü

* ayrıca özet tablo

* mümkünse kullanılan tool/version bilgisi de görünsün

**3\) Waveform görüntülerinin hazırlanması**  
Makale için anlamlı waveform ekran görüntüleri gerekiyor. En az 2–3 adet hazırlayın.

Öncelikli waveform senaryoları:

* DQN start → busy → done akışı

* ağırlık yükleme işlemi (WT\_ADDR / WT\_DATA)

* inference sonucu oluşumu (QVAL ve argmax)

* mümkünse AXI read/write handshake örneği

Beklenenler:

* sinyal isimleri net görünsün

* ekran görüntüsü temiz olsun

* mümkünse kısa açıklama notu eklensin

**4\) Performans verilerinin hazırlanması**  
Aşağıdaki verileri düzenli şekilde paylaşın:

* maze boyutlarına göre ham cycle verileri

* core-only ve DQN karşılaştırma tablosu

* speedup hesapları

* grafik üretimine uygun CSV / Excel dosyası

Mümkünse ayrıca hazır grafikler de paylaşın:

* cycle karşılaştırma grafiği

* speedup grafiği

**5\) DQN eğitim ve veri üretim bilgisinin yazılması**  
Bu kısım makale için kritik. Yazılı olarak şu bilgileri hazırlayın:

* state tanımı (4 giriş tam olarak neyi temsil ediyor?)

* 4 çıkışın anlamı

* eğitim yöntemi (DQN / teacher-based / başka yöntem)

* reward yapısı

* veri üretim yöntemi

* kullanılan maze / dataset bilgisi

* quantization süreci (float → Q1.15)

* weight export ve RTL’e yükleme akışı

Ayrıca, performans testinde kullanılan gerçek ağırlık setinin hangi dosyadan ve hangi akışla üretildiğini de açıkça belirtin.

**6\) FPGA / implementation raporlarının paylaşılması**  
Gönderdiğiniz create\_project.tcl dosyası Vivado proje oluşturma ve FPGA hedefli akışın tanımlı olduğunu gösteriyor. Bu nedenle varsa aşağıdaki raporları da paylaşın:

* LUT

* FF

* BRAM

* DSP

* Fmax

* timing report

* power estimate

* utilization report

* implementation summary

Bunlar makalenin teknik gücünü önemli ölçüde artıracaktır.

**7\) Board üzerinde çalışma kanıtları**

* board üzerinde çalışan tasarımın kısa videosu

* board fotoğrafı

* UART / seri terminal çıktısı ekran görüntüsü

* bitstream yükleme veya implementation başarısını gösteren ekran görüntüleri

Not:

* video kısa demo şeklinde olabilir

* bu materyaller destekleyici kanıt olarak çok faydalı olacaktır

**8\) Kalite / başarı ölçümleri**  
Sadece hız değil, doğruluk / başarı tarafı da önemli. Varsa şu metrikleri paylaşın:

* maze çözme başarı oranı

* hedefe ulaşma oranı

* BFS ile kalite karşılaştırması

* ortalama adım sayısı

* optimum yola yakınlık

