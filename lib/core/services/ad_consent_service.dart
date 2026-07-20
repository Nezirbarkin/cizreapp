import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob için GDPR/CCPA kullanıcı onayı (UMP) ve iOS App Tracking
/// Transparency (ATT) akışını yönetir.
///
/// `MobileAds.instance.initialize()` çağrılmadan ÖNCE bu servisin
/// [requestConsentAndTracking] metodu tamamlanmalı; aksi halde AdMob'un
/// EU User Consent Policy'si ihlal edilir (kullanıcıya sorulmadan
/// kişiselleştirilmiş reklam SDK'sı başlatılmış olur).
class AdConsentService {
  /// UMP formunu (varsa) gösterir ve ardından iOS'ta ATT iznini ister.
  /// Her adım en fazla birkaç saniye sürer; hata durumunda sessizce devam
  /// eder ki reklam SDK'sı hiç başlamama riskiyle karşılaşılmasın.
  Future<void> requestConsentAndTracking() async {
    await _requestUmpConsent();
    if (Platform.isIOS) {
      await _requestAppTrackingTransparency();
    }
  }

  Future<void> _requestUmpConsent() async {
    final completer = Completer<void>();
    final params = ConsentRequestParameters();

    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        try {
          final formAvailable = await ConsentInformation.instance
              .isConsentFormAvailable();
          if (formAvailable) {
            await _loadAndShowConsentForm();
          }
        } catch (e) {
          log('⚠️ UMP consent form gösterilemedi: $e');
        } finally {
          if (!completer.isCompleted) completer.complete();
        }
      },
      (error) {
        log('⚠️ UMP consent bilgisi alınamadı: ${error.message}');
        if (!completer.isCompleted) completer.complete();
      },
    );

    return completer.future;
  }

  Future<void> _loadAndShowConsentForm() {
    final completer = Completer<void>();

    ConsentForm.loadConsentForm(
      (consentForm) async {
        final status = await ConsentInformation.instance.getConsentStatus();
        if (status == ConsentStatus.required) {
          consentForm.show((formError) {
            if (formError != null) {
              log('⚠️ UMP consent form hatası: ${formError.message}');
            }
            if (!completer.isCompleted) completer.complete();
          });
        } else {
          if (!completer.isCompleted) completer.complete();
        }
      },
      (formError) {
        log('⚠️ UMP consent form yüklenemedi: ${formError.message}');
        if (!completer.isCompleted) completer.complete();
      },
    );

    return completer.future;
  }

  Future<void> _requestAppTrackingTransparency() async {
    try {
      final status =
          await AppTrackingTransparency.trackingAuthorizationStatus;
      if (status == TrackingStatus.notDetermined) {
        await AppTrackingTransparency.requestTrackingAuthorization();
      }
    } catch (e) {
      log('⚠️ ATT izin isteği başarısız: $e');
    }
  }
}
