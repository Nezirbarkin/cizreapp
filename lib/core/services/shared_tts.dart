import 'package:flutter_tts/flutter_tts.dart';

FlutterTts? _shared;

/// Uygulamadaki TEK [FlutterTts] örneği.
///
/// flutter_tts her örnekte aynı `flutter_tts` platform kanalına kendi geri
/// çağrı işleyicisini bağlar; son oluşturulan örnek öncekilerin "bitti /
/// iptal" olaylarını çalar ve yerel motor (ses, ton) zaten ortaktır. Okey
/// masası anonsları ve sesli duyurular bu yüzden aynı örneği kullanır.
FlutterTts sharedFlutterTts() => _shared ??= FlutterTts();
