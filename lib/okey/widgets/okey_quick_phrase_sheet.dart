import 'package:flutter/material.dart';

import '../theme/okey_theme.dart';
import '../theme/okey_ui.dart';

/// HIZLI MESAJ — kullanıcı isteği, 2026-09-14: "'Seri Lütfen', 'Tebrikler',
/// 'Bol Şanslar' vb. butonlar koy (sesli olsun)".
///
/// ## Neden hazır cümleler, serbest metin değil
///
/// Serbest metin hem moderasyon (küfür/taciz) hem TTS güvenilirliği
/// (Türkçe motor rastgele yazılan her şeyi doğru okumaz) sorunu açar.
/// Kapalı bir cümle listesi ikisini de baştan çözer: her cümle önceden
/// seslendirilmeye uygun, kısa ve masadaki bir ana karşılık gelir.
///
/// ## Neden alıcı seçilmiyor (hediyenin aksine)
///
/// Hediye BELİRLİ bir oyuncuya gider (bkz. OkeyGiftSheet — "kime" sorusu
/// var). Bir hızlı mesaj ise MASAYA söylenir: "Bol şanslar" tek bir kişiye
/// değil, oturan herkese seslenir. Alıcı seçtirmek gereksiz bir adım
/// eklerdi.
class OkeyQuickPhraseSheet extends StatelessWidget {
  /// Gönderim geri çağrısı — provider.sendQuickPhrase'e bağlanır.
  final void Function(String phrase) onSend;

  const OkeyQuickPhraseSheet({super.key, required this.onSend});

  /// Hazır cümleler — her biri kısa, TTS'e uygun ve masadaki gerçek bir ana
  /// karşılık gelir (kullanıcının verdiği üç örnek + doğal tamamlayıcılar).
  static const List<(String emoji, String text)> phrases = [
    ('🍀', 'Bol Şanslar'),
    ('💪', 'Kolay Gelsin'),
    ('⏱️', 'Seri Lütfen'),
    ('🎉', 'Tebrikler'),
    ('👏', 'Aferin'),
    ('🔥', 'Harika Oyun'),
    ('😅', 'Üzgünüm'),
    ('🙏', 'Teşekkürler'),
  ];

  static Future<void> show(
    BuildContext context, {
    required void Function(String phrase) onSend,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => OkeyQuickPhraseSheet(onSend: onSend),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final screen = MediaQuery.sizeOf(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          margin: const EdgeInsets.all(10),
          constraints: BoxConstraints(maxHeight: screen.height * 0.7),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [const Color(0xFF16556E), OkeyColors.screenBackground],
            ),
            borderRadius: BorderRadius.circular(OkeyUI.radiusLg),
            border: Border.all(color: OkeyUI.cardBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.record_voice_over,
                      size: 18,
                      color: Color(0xFFFFD54F),
                    ),
                    const SizedBox(width: 7),
                    const Expanded(
                      child: Text('HIZLI MESAJ', style: OkeyUI.title),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: OkeyUI.textFaint),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Masadaki herkes görür ve duyar.',
                  style: OkeyUI.caption,
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (emoji, text) in phrases)
                        _PhraseChip(
                          emoji: emoji,
                          text: text,
                          onTap: () {
                            Navigator.of(context).pop();
                            onSend(text);
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhraseChip extends StatelessWidget {
  final String emoji;
  final String text;
  final VoidCallback onTap;

  const _PhraseChip({
    required this.emoji,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: OkeyUI.cardFillRaised,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: OkeyUI.cardBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
