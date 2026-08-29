APP_NAME   := Aishow
BUNDLE_ID  := com.openhome.aishow
BUILD_DIR  := .build/release
DIST       := dist
APP        := $(DIST)/$(APP_NAME).app
## 署名 ID。ad-hoc("-")は cdhash 固定要件になり、再ビルドごとに TCC(Accessibility)の許可が無効化される。
## 自己署名証明書を作って `make app SIGN_IDENTITY="My Local Dev"` とすると識別子ベースの要件になり許可が持続する。
SIGN_IDENTITY ?= -

.PHONY: build test run app clean harness

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

## TrueForge をローカル起動(別ターミナルで)
harness:
	npx @truefoundry/trueforge@latest

clean:
	rm -rf .build $(DIST)
