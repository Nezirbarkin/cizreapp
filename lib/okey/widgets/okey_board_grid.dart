/// Oyun tahtasındaki IZGARA HÜCRESİNİN ölçüsü.
///
/// TEK KAYNAK: Hem ızgarayı çizen [_GridPainter] hem de açılan perleri
/// yerleştiren yerleşim bu sabitleri kullanır. Böylece perler ızgaranın
/// kutucuklarına TAM oturur.
///
/// NEDEN AYRI BİR DOSYA: Izgara önce yalnızca dekoratif bir çizimdi (sabit
/// 26px adım) ve perler ondan bağımsız diziliyordu; taşlar kutucuklarla
/// hizalanmıyordu. Ölçü iki yerde ayrı yazılsaydı biri değişip diğeri
/// unutulduğunda hizalama sessizce bozulurdu — ıstaka süslemesinde (bkz.
/// okey_rack_chrome.dart) tam olarak bu hata yaşanmıştı.
library;

import 'package:flutter/widgets.dart';

/// Izgara çiziminin kimliği — testler hizalamayı bu çizimin köşesinden ölçer.
const Key okeyBoardGridKey = ValueKey('okey_board_grid');

/// Bir hücrenin genişliği — masadaki küçük taş (30) + iki yanında 2'şer pay.
const double okeyBoardCellWidth = 34;

/// Bir hücrenin yüksekliği — küçük taş (40) + üstünde/altında 2'şer pay.
const double okeyBoardCellHeight = 44;

/// Taşın hücre içindeki kenar payı (her yönde).
const double okeyBoardCellInset = 2;

/// Hücreye oturan taşın çizim ölçüleri.
const double okeyBoardTileWidth = okeyBoardCellWidth - (okeyBoardCellInset * 2);
const double okeyBoardTileHeight =
    okeyBoardCellHeight - (okeyBoardCellInset * 2);
