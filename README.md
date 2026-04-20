# Computer-with-8086-Microprocessor
8086 mikroişlemciyi bir bilgisayarmış gibi kullanabilme özellikleri bulundurma.(Güvenlik,Klavye, Hesap Makinesi, Oyun Oynama, Haberleşme Yapabilme).
Donanım Mimarisi
Sistemin içerisinde bulunan entegrelerin özellikleri ve işlevleri:
INTEL 8086 CPU : Master ve Slave konfigürasyonunda çift işlemci mimarisi.
8251A USART : İşlemciler Arası Seri Haberleşme , Veri Alışverişi Yapabilme.
8259 PIC : Kesme tabanlı (Interrupt) klavye girişi ve gerçek zamanlı olay yönetimi.
8255 PPI : 16x2 LCD ekran sürücüleri ve G/Ç port yönetimi.
74154 Decoder: 4-to-16 hat çözücü ile gelişmiş I/O adreslemesi.
Basit gibi görünen sistemin çalışma durumunun detayları:
Güvenl Giriş Sistemi : Sistem B üzerinden PIN tabanlı kullanıcı doğrulama ve yetkilendirme.Klavye tuş konfigürasyonlarında tanımlanan değerlerinin assembly üzerinden belirlenen şifre ile birebir uyumunda aktif olması.
Gelişmiş Haberleşme: Sistem B üzerinden girilen verilerin USART üzerinden gerçek zamanlı olarak Sistem A'ya aktarılması ya da bu durumun tam tersi şekilde haberleşmesi.
Oyun Modu: İşlemci mimarisi üzerinde koşan düşük seviyeli oyun mantığı.
Hesap Makinesi: Aritmetik işlemlerin assembly seviyesinde işlenmesi.
Klavye & Yazı Modu: Karakterlerin tampon belleğe alınması ve LCD üzerinde dinamik olarak görüntülenmesi.
Tüm sürücüler ve uygulama mantığı optimize edilmiş 8086 Assembly dili ile yazılmıştır.
