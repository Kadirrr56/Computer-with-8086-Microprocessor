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
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
The system includes features that allow the 8086 microprocessor to be used as if it were a computer (Security, Keyboard, Calculator, Gaming, Communication).
Hardware Architecture
Features and functions of the integrated circuits in the system:
INTEL 8086 CPU: Dual processor architecture in Master and Slave configuration.
8251A USART: Serial communication and data exchange between processors.
8259 PIC: Interrupt-based keyboard input and real-time event management.
8255 PPI: 16x2 LCD screen drivers and I/O port management.
74154 Decoder: Advanced I/O addressing with a 4-to-16 line decoder.
Details of the seemingly simple system's operation:
Secure Login System: PIN-based user authentication and authorization via System B. Activation occurs when the values ​​defined in the keyboard key configurations match the password defined via assembly. Advanced Communication: Data entered from System B is transferred to System A in real time via USART, or vice versa.
Gaming Mode: Low-level gaming logic running on the processor architecture.
Calculator: Arithmetic operations are processed at the assembly level.
Keyboard & Typing Mode: Characters are stored in buffer memory and dynamically displayed on the LCD. All drivers and application logic are written in optimized 8086 Assembly language.
