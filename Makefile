APP_NAME   := Aishow
BUNDLE_ID  := com.openhome.aishow
BUILD_DIR  := .build/release
DIST       := dist
APP        := $(DIST)/$(APP_NAME).app
## 署名 ID。ad-hoc("-")は cdhash 固定要件になり、再ビルドごとに TCC(Accessibility)の許可が無効化される。
## Keychain に「… Local Dev」という自己署名証明書があれば自動で使う(識別子ベースの要件になり許可が持続する)。
## 明示する場合は `make app SIGN_IDENTITY="My Local Dev"`。
LOCAL_DEV_ID  := $(shell security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(.*Local Dev\)".*/\1/p' | head -1)
SIGN_IDENTITY ?= $(if $(LOCAL_DEV_ID),$(LOCAL_DEV_ID),-)
## `make install` の置き場。パスも固定にすることで TCC の許可が再ビルド後も持続する
INSTALL_DIR   ?= $(HOME)/Applications

.PHONY: build test run app install reset-tcc clean harness

build:
	swift build

test:
	swift test

run: build
	.build/debug/aishow $(ARGS)

## Step 6: メニューバー常駐アプリを .app に包む(Xcode プロジェクト不要、既定 ad-hoc 署名。SIGN_IDENTITY で上書き可)
## TCC(マイク / Accessibility / Automation)の許可は bundle id 単位なので .app 化が必須
app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BUILD_DIR)/aishow $(APP)/Contents/MacOS/$(APP_NAME)
	sed -e 's/__BUNDLE_ID__/$(BUNDLE_ID)/' -e 's/__APP_NAME__/$(APP_NAME)/' scripts/Info.plist.template > $(APP)/Contents/Info.plist
	mkdir -p $(APP)/Contents/Resources/harness
	rsync -a --exclude='.env' harness/ $(APP)/Contents/Resources/harness/
	codesign --force --deep --sign "$(SIGN_IDENTITY)" $(APP)
	@echo "built $(APP)  (open $(APP) で起動)"

## 固定パス(~/Applications)に置いて再起動。署名(自己署名証明書)とパスが固定なので、
## Accessibility / マイク / Automation の許可は再ビルド後もそのまま効く(VoiceInk と同じ運用)
install: app
	mkdir -p $(INSTALL_DIR)
	-osascript -e 'tell application id "$(BUNDLE_ID)" to quit' >/dev/null 2>&1; sleep 1
	rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	cp -R $(APP) $(INSTALL_DIR)/$(APP_NAME).app
	open $(INSTALL_DIR)/$(APP_NAME).app
	@echo "installed $(INSTALL_DIR)/$(APP_NAME).app  (署名: $(SIGN_IDENTITY))"

## TCC の許可を初回状態に戻す(署名を ad-hoc から証明書に切り替えた直後など、古い許可が残って混乱するときに 1 回)
reset-tcc:
	-tccutil reset Accessibility $(BUNDLE_ID)
	-tccutil reset Microphone $(BUNDLE_ID)
	-tccutil reset AppleEvents $(BUNDLE_ID)

## TrueForge をローカル起動(別ターミナルで)
harness:
	npx @truefoundry/trueforge@latest

clean:
	rm -rf .build $(DIST)
