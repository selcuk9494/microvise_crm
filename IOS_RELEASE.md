# iOS Release (TestFlight / App Store)

## Gerekenler

- macOS + Xcode (Apple Developer hesabı ile giriş yapılmış olmalı)
- Proje: `ios/Runner.xcworkspace`
- Bundle ID: `com.microvise.microviseCrm`
- Version/Build: `pubspec.yaml` içindeki `version` alanı

## Hızlı Yol (IPA export)

Terminal:

```bash
chmod +x scripts/ios_build_ipa.sh
./scripts/ios_build_ipa.sh
```

Çıktı klasörü:

- `build/ios/ipa/` (IPA burada oluşur)

## Xcode ile TestFlight

- `ios/Runner.xcworkspace` aç
- `Runner` target → Signing & Capabilities:
  - Automatically manage signing: açık
  - Team: doğru takım seçili
- Product → Archive
- Archive ekranı → Distribute App → App Store Connect → Upload

