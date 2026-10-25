TARGET = iphone:clang:latest:16.0
INSTALL_TARGET_PROCESSES = External-DarkSword
ARCHS = arm64e
DEBUG = 0
FINALPACKAGE = 1
FOR_RELEASE = 1
_THEOS_OBJ_FILE_TAG = arm64e

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME_REAL = External-DarkSword
APPLICATION_NAME = External_DarkSword

$(APPLICATION_NAME)_BUNDLE_NAME = External-DarkSword
$(APPLICATION_NAME)_FILES = \
	AppImageCatalog.swift \
	ContentView.swift \
	UI/Localization/AppStrings.swift \
	UI/Theme/AppPalette.swift \
	UI/Components/SharedUI.swift \
	UI/Components/DebugKernelPanel.swift \
	UI/Components/GameCard.swift \
	UI/Screens/ExploitScreen.swift \
	UI/Screens/GameListScreen.swift \
	UI/Screens/LogScreen.swift \
	DarkSwordManager.swift \
	External_DarkSwordApp.swift \
	funcs/keepalive.swift \
	App/Storage/AppUserDefaults.m \
	App/Configuration/Config.c \
	Core/darksword.m \
	Core/utils.m \
	App/Notifications/AppNotifications.m \
	Core/offsets.m \
	Core/persistence.m \
	Core/TaskRop/RemoteCall.m \
	Core/TaskRop/thread.m \
	Core/TaskRop/vm.m \
	Core/TaskRop/exc.m \
	Core/TaskRop/pac.m \
	Core/pe/vnode.m \
	Features/Games/AoV/AoVManager.mm \
	Features/Games/AoV/Heroes/AoVHeroNameResolver.m \
	Features/Games/FreeFire/FreeFireManager.mm \
	Features/Overlay/OverlayWebSocketServer.m \
	Features/Overlay/RemoteWebViewOverlay.m
$(APPLICATION_NAME)_FRAMEWORKS = UIKit Foundation CoreFoundation Security AVFoundation CoreGraphics QuartzCore Metal MetalKit
$(APPLICATION_NAME)_LIBRARIES = xpf grabkernel2
$(APPLICATION_NAME)_CFLAGS = -fobjc-arc -Wno-error=deprecated-declarations -Wno-error=unused-variable -Wno-error=unused-function -Wno-error=unused-but-set-variable -Wno-error=unused-const-variable -Wno-error=incompatible-pointer-types -ICore -ICore/TaskRop -ICore/pe -ICore/headers -ICore/headers/choma
Features/Games/AoV/AoVManager.mm_CFLAGS = -std=c++17
Features/Games/FreeFire/FreeFireManager.mm_CFLAGS = -std=c++17
$(APPLICATION_NAME)_SWIFTFLAGS = -import-objc-header $(THEOS_PROJECT_DIR)/External-DarkSword-Bridging-Header.h
$(APPLICATION_NAME)_LDFLAGS = -L$(THEOS_PROJECT_DIR)/Resources/Frameworks -Wl,-rpath,@executable_path/Frameworks
$(APPLICATION_NAME)_CODESIGN_FLAGS = -S$(THEOS_PROJECT_DIR)/External-DarkSword.entitlements

include $(THEOS_MAKE_PATH)/application.mk

after-stage::
	@if [ -d "$(THEOS_STAGING_DIR)/Applications/$(APPLICATION_NAME_REAL).app/AppIcon" ]; then \
		mv $(THEOS_STAGING_DIR)/Applications/$(APPLICATION_NAME_REAL).app/AppIcon/*.png \
			$(THEOS_STAGING_DIR)/Applications/$(APPLICATION_NAME_REAL).app/ 2>/dev/null || true; \
		rmdir $(THEOS_STAGING_DIR)/Applications/$(APPLICATION_NAME_REAL).app/AppIcon 2>/dev/null || true; \
	fi
	@xcrun ibtool --compile $(THEOS_STAGING_DIR)/Applications/$(APPLICATION_NAME_REAL).app/LaunchScreen.storyboardc \
		--target-device iphone --target-device ipad --minimum-deployment-target 16.0 \
		$(THEOS_PROJECT_DIR)/Resources/LaunchScreen.storyboard

after-package::
	@echo "[*] Zipping application..."
	@rm -rf Payload
	@rm -f $(APPLICATION_NAME_REAL).ipa packages/$(APPLICATION_NAME_REAL).ipa
	@mkdir -p Payload
	@cp -R .theos/_/Applications/$(APPLICATION_NAME_REAL).app Payload/
	@chmod 755 Payload/$(APPLICATION_NAME_REAL).app/$(APPLICATION_NAME)
	@zip -rq $(APPLICATION_NAME_REAL).ipa Payload
	@rm -rf Payload
	@mkdir -p packages
	@mv $(APPLICATION_NAME_REAL).ipa packages/
	@rm -f packages/*.deb
	@echo "[*] Success: packages/$(APPLICATION_NAME_REAL).ipa"
