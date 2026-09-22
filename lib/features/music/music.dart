/// Müzik özelliğinin dışarıya açık yüzü.
///
/// Diğer özellikler (gönderi, hikaye, yan menü, admin) müziği YALNIZCA bu
/// dosya üzerinden kullanır. Tek kapı olması, özelliğin iç yapısını —
/// hangi servisin neyi yaptığını, kliplerin nasıl kesildiğini — değiştirirken
/// uygulamanın geri kalanına dokunmamayı sağlıyor.
library;

export 'models/attached_music.dart';
export 'models/music_track.dart';
export 'screens/artist_upload_screen.dart';
export 'screens/music_player_screen.dart';
export 'screens/my_music_screen.dart';
export 'services/clip_player.dart';
export 'services/music_attach_service.dart';
export 'services/music_catalog_service.dart';
export 'services/music_library_service.dart';
export 'services/music_settings_service.dart';
export 'widgets/music_chips.dart';
export 'widgets/music_picker_sheet.dart';
export 'widgets/music_player_widgets.dart';
export 'widgets/music_ui.dart';
