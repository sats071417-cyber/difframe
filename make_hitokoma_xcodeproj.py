#!/usr/bin/env python3
"""Create Hitokoma.xcodeproj (SwiftUI iOS app + widget extension).

Usage: python3 make_hitokoma_xcodeproj.py <project-root>

Layout under <project-root>:
  Hitokoma/         app sources and resources
  HitokomaWidget/   widget extension sources
  Shared/           files compiled into both targets

Settings that must survive regeneration (team, bundle id, App Group) live in
  hitokoma.config.json   (next to this script)  or environment variables:
  {
    "bundle_id": "com.yourname.hitokoma",   // HITOKOMA_BUNDLE_ID
    "development_team": "ABCDE12345",       // HITOKOMA_TEAM
    "app_group": false                      // HITOKOMA_APP_GROUP=1  (needs the App Groups capability)
  }
"""
import hashlib
import json
import os
import sys

APP = "Hitokoma"
WIDGET = "HitokomaWidget"

APP_SOURCES = ["HitokomaApp.swift", "ContentView.swift", "TodayView.swift", "CloudIDs.swift", "ContactsOnboarding.swift", "FriendsHub.swift",
               "FriendsView.swift", "WorldMapView.swift",
               "PostStore.swift", "CalendarView.swift", "NotificationScheduler.swift",
               "FriendCode.swift", "PromptArt.swift", "PromptVerifier.swift", "ProfileView.swift",
               "Achievements.swift", "Theme.swift", "WorldView.swift", "WorldPin.swift", "MorningPickup.swift", "LocationMap.swift",
               "CaptureFlow.swift", "WidgetBridge.swift", "OnboardingView.swift", "PromptCatalog.swift",
               "Account.swift", "SignUpView.swift", "ContactsView.swift", "Localization.swift", "LocalizedEN.swift", "LocalizedZH.swift", "LocalizedKO.swift", "LocalizedES.swift", "LocalizedFR.swift", "TimelineScreen.swift", "Social.swift", "CityLocator.swift", "GlobeView.swift", "SettingsView.swift", "ShareCard.swift", "CloudConfig.swift", "Cloud.swift", "CloudViews.swift", "FriendList.swift", "CloudInbox.swift", "InboxViews.swift", "ChatMedia.swift", "BackgroundSync.swift", "LiveActivityBridge.swift", "FriendInviteCard.swift", "PushRegistration.swift", "PushRouter.swift", "FirebasePhone.swift", "Sun.swift", "AccountDeletion.swift", "GalleryStyle.swift", "AIFeatures.swift"]
def ftype(name):
    if name.endswith('.plist'): return 'text.plist.xml'
    return 'folder.assetcatalog' if name.endswith('.xcassets') else 'text.json'


APP_RESOURCES = ["Assets.xcassets", "GoogleService-Info.plist", "PrivacyInfo.xcprivacy"]
WIDGET_RESOURCES = ["PrivacyInfo.xcprivacy"]
FIREBASE_URL = "https://github.com/firebase/firebase-ios-sdk"
WIDGET_SOURCES = ["HitokomaWidget.swift"]
SHARED_SOURCES = ["WidgetSnapshot.swift", "AppGroup.swift", "PromptActivity.swift"]
LOCATION_REASON = "Difframe uses your location to show where you are on the map and to add your city name (like Tokyo) to posts. Your exact location is never sent."
CONTACTS_REASON = "Difframe uses your contacts to find friends who use Difframe and to choose who to invite. Phone numbers are matched in a form that cannot be read back, and names are never uploaded."
CAMERA_REASON = "Difframe uses the camera to take the photo for today's prompt."
PHOTOS_REASON = "Difframe saves your posts to your photo library when you ask it to."
MIC_REASON = "Difframe uses the microphone to record voice messages."
# Translations of the permission dialogs (InfoPlist.strings). English is the base (build settings above).
PERMISSION_TEXT = {
    "ja": {"NSCameraUsageDescription": "お題に合わせて、その場で写真を撮るために使います。",
           "NSContactsUsageDescription": "連絡先の中から Difframe を使っている友達を探したり、招待する相手を選んだりするために使います。電話番号は読めない形に変えて照合し、名前は送りません。",
           "NSLocationWhenInUseUsageDescription": "地図であなたのいる場所を示したり、投稿に都市の名前（例：東京）をつけるために使います。正確な位置は送信しません。",
           "NSPhotoLibraryAddUsageDescription": "自分の投稿を、写真アプリに保存するために使います。",
           "NSMicrophoneUsageDescription": "ボイスメッセージを録音するために使います。"},
    "zh-Hans": {"NSCameraUsageDescription": "Difframe 使用相机拍摄今天题目的照片。",
                "NSContactsUsageDescription": "Difframe 使用通讯录查找在用 Difframe 的朋友，并选择要邀请的人。手机号会转换成无法读取的形式再比对，不会上传名字。",
                "NSLocationWhenInUseUsageDescription": "Difframe 使用你的位置在地图上显示你所在的地方，并在帖子中添加城市名称（例如东京）。不会发送精确位置。",
                "NSPhotoLibraryAddUsageDescription": "Difframe 会在你需要时把帖子保存到照片图库。",
                "NSMicrophoneUsageDescription": "Difframe 使用麦克风录制语音消息。"},
    "ko": {"NSCameraUsageDescription": "Difframe은 오늘의 주제 사진을 찍기 위해 카메라를 사용해요.",
           "NSContactsUsageDescription": "Difframe은 연락처에서 Difframe을 쓰는 친구를 찾고 초대할 사람을 고르기 위해 연락처를 사용해요. 전화번호는 읽을 수 없는 형태로 바꿔 대조하고, 이름은 보내지 않아요.",
           "NSLocationWhenInUseUsageDescription": "Difframe은 지도에 내 위치를 표시하고 게시물에 도시 이름(예: 도쿄)을 붙이기 위해 위치를 사용해요. 정확한 위치는 보내지 않아요.",
           "NSPhotoLibraryAddUsageDescription": "Difframe은 요청할 때 게시물을 사진 보관함에 저장해요.",
           "NSMicrophoneUsageDescription": "Difframe은 음성 메시지를 녹음하기 위해 마이크를 사용해요."},
    "es": {"NSCameraUsageDescription": "Difframe usa la cámara para hacer la foto del tema de hoy.",
           "NSContactsUsageDescription": "Difframe usa tus contactos para encontrar amigos que usan Difframe y elegir a quién invitar. Los números se comparan en una forma ilegible y los nombres nunca se envían.",
           "NSLocationWhenInUseUsageDescription": "Difframe usa tu ubicación para mostrar dónde estás en el mapa y añadir el nombre de tu ciudad (por ejemplo, Tokio) a tus publicaciones. Nunca se envía tu ubicación exacta.",
           "NSPhotoLibraryAddUsageDescription": "Difframe guarda tus publicaciones en la fototeca cuando se lo pides.",
           "NSMicrophoneUsageDescription": "Difframe usa el micrófono para grabar mensajes de voz."},
    "fr": {"NSCameraUsageDescription": "Difframe utilise l'appareil photo pour prendre la photo du thème du jour.",
           "NSContactsUsageDescription": "Difframe utilise tes contacts pour trouver les amis qui utilisent Difframe et choisir qui inviter. Les numéros sont comparés sous une forme illisible et les noms ne sont jamais envoyés.",
           "NSLocationWhenInUseUsageDescription": "Difframe utilise ta position pour te montrer sur la carte et ajouter le nom de ta ville (par exemple Tokyo) à tes publications. Ta position exacte n'est jamais envoyée.",
           "NSPhotoLibraryAddUsageDescription": "Difframe enregistre tes publications dans la photothèque quand tu le demandes.",
           "NSMicrophoneUsageDescription": "Difframe utilise le micro pour enregistrer des messages vocaux."},
}


def uid(key: str) -> str:
    return hashlib.md5(key.encode()).hexdigest()[:24].upper()


def load_config(script_dir: str) -> dict:
    config = {"bundle_id": "com.example.hitokoma", "development_team": "", "app_group": False}
    path = os.path.join(script_dir, "hitokoma.config.json")
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            config.update(json.load(f))
    if os.environ.get("HITOKOMA_BUNDLE_ID"):
        config["bundle_id"] = os.environ["HITOKOMA_BUNDLE_ID"]
    if os.environ.get("HITOKOMA_TEAM"):
        config["development_team"] = os.environ["HITOKOMA_TEAM"]
    if os.environ.get("HITOKOMA_APP_GROUP"):
        config["app_group"] = os.environ["HITOKOMA_APP_GROUP"] == "1"
    return config


def write_text(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


PLIST_HEAD = ('<?xml version="1.0" encoding="UTF-8"?>\n'
              '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
              '<plist version="1.0">\n<dict>\n')
PLIST_TAIL = "</dict>\n</plist>\n"

PRIVACY_HEAD = PLIST_HEAD.replace("<dict>", "<dict>")
PRIVACY_APP = (PLIST_HEAD +
    "\t<key>NSPrivacyTracking</key>\n\t<false/>\n"
    "\t<key>NSPrivacyTrackingDomains</key>\n\t<array/>\n"
    "\t<key>NSPrivacyCollectedDataTypes</key>\n\t<array>\n"
    + "".join(
        "\t\t<dict>\n\t\t\t<key>NSPrivacyCollectedDataType</key>\n\t\t\t<string>" + t + "</string>\n"
        "\t\t\t<key>NSPrivacyCollectedDataTypeLinked</key>\n\t\t\t<true/>\n"
        "\t\t\t<key>NSPrivacyCollectedDataTypeTracking</key>\n\t\t\t<false/>\n"
        "\t\t\t<key>NSPrivacyCollectedDataTypePurposes</key>\n\t\t\t<array>\n\t\t\t\t<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>\n\t\t\t</array>\n"
        "\t\t</dict>\n"
        # App Store Connect の「App のプライバシー」と同じ8種類（メールアドレス・正確な位置・連絡先は集めない）
        for t in ["NSPrivacyCollectedDataTypeName", "NSPrivacyCollectedDataTypePhoneNumber",
                  "NSPrivacyCollectedDataTypeCoarseLocation", "NSPrivacyCollectedDataTypePhotosorVideos",
                  "NSPrivacyCollectedDataTypeAudioData", "NSPrivacyCollectedDataTypeEmailsOrTextMessages",
                  "NSPrivacyCollectedDataTypeUserID", "NSPrivacyCollectedDataTypeOtherUserContent"])
    + "\t</array>\n"
    "\t<key>NSPrivacyAccessedAPITypes</key>\n\t<array>\n"
    "\t\t<dict>\n\t\t\t<key>NSPrivacyAccessedAPIType</key>\n\t\t\t<string>NSPrivacyAccessedAPICategoryUserDefaults</string>\n"
    "\t\t\t<key>NSPrivacyAccessedAPITypeReasons</key>\n\t\t\t<array>\n\t\t\t\t<string>CA92.1</string>\n\t\t\t</array>\n\t\t</dict>\n"
    "\t</array>\n" + PLIST_TAIL)
PRIVACY_WIDGET = (PLIST_HEAD +
    "\t<key>NSPrivacyTracking</key>\n\t<false/>\n"
    "\t<key>NSPrivacyTrackingDomains</key>\n\t<array/>\n"
    "\t<key>NSPrivacyCollectedDataTypes</key>\n\t<array/>\n"
    "\t<key>NSPrivacyAccessedAPITypes</key>\n\t<array>\n"
    "\t\t<dict>\n\t\t\t<key>NSPrivacyAccessedAPIType</key>\n\t\t\t<string>NSPrivacyAccessedAPICategoryUserDefaults</string>\n"
    "\t\t\t<key>NSPrivacyAccessedAPITypeReasons</key>\n\t\t\t<array>\n\t\t\t\t<string>CA92.1</string>\n\t\t\t</array>\n\t\t</dict>\n"
    "\t</array>\n" + PLIST_TAIL)


def main() -> None:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    config = load_config(script_dir)
    bundle_id = config["bundle_id"]
    widget_bundle_id = bundle_id + ".widget"
    team = config["development_team"]
    use_group = bool(config["app_group"])
    group_id = "group." + bundle_id

    root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
    dirs = {APP: os.path.join(root, APP), WIDGET: os.path.join(root, WIDGET), "Shared": os.path.join(root, "Shared")}

    # ---- files written by the generator
    write_text(os.path.join(dirs["Shared"], "AppGroup.swift"),
               "import Foundation\n\n/// アプリとウィジェットでデータを共有する App Group（生成されたファイル）\n"
               "enum AppGroup {\n    static let id: String? = " + (f'"{group_id}"' if use_group else "nil") + "\n}\n")
    write_text(os.path.join(dirs[APP], "Info.plist"),
               PLIST_HEAD +
               "\t<key>CFBundleURLTypes</key>\n\t<array>\n\t\t<dict>\n"
               "\t\t\t<key>CFBundleURLName</key>\n\t\t\t<string>" + bundle_id + "</string>\n"
               "\t\t\t<key>CFBundleURLSchemes</key>\n\t\t\t<array>\n\t\t\t\t<string>hitokoma</string>\n\t\t\t\t<string>app-1-4593850939-ios-17a417c2fb93002bf41a1e</string>\n\t\t\t</array>\n"
               "\t\t</dict>\n\t</array>\n"
               "\t<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>fetch</string>\n\t\t<string>remote-notification</string>\n\t</array>\n"
               "\t<key>BGTaskSchedulerPermittedIdentifiers</key>\n\t<array>\n\t\t<string>" + bundle_id + ".refresh</string>\n\t</array>\n"
               "\t<key>UISupportedInterfaceOrientations</key>\n\t<array>\n\t\t<string>UIInterfaceOrientationPortrait</string>\n\t</array>\n"
               "\t<key>ITSAppUsesNonExemptEncryption</key>\n\t<false/>\n"
               "\t<key>CFBundleDevelopmentRegion</key>\n\t<string>en</string>\n"
               "\t<key>CFBundleLocalizations</key>\n\t<array>\n" + "".join(f"\t\t<string>{l}</string>\n" for l in ["en", "ja", "zh-Hans", "ko", "es", "fr"]) + "\t</array>\n"
               + PLIST_TAIL)
    # 許可の画面の文の訳（英語は、ビルド設定の文がそのまま使われる）
    for lang, texts in PERMISSION_TEXT.items():
        body = "".join('"' + k + '" = "' + v.replace('"', '\\"') + '";\n' for k, v in texts.items())
        write_text(os.path.join(dirs[APP], lang + ".lproj", "InfoPlist.strings"), body)
    # App Store：アプリが集めるデータと、理由のある API（UserDefaults）の申告。Apple の審査に必要
    write_text(os.path.join(dirs[APP], "PrivacyInfo.xcprivacy"), PRIVACY_APP)
    write_text(os.path.join(dirs[WIDGET], "PrivacyInfo.xcprivacy"), PRIVACY_WIDGET)
    write_text(os.path.join(dirs[WIDGET], "Info.plist"),
               PLIST_HEAD +
               "\t<key>NSExtension</key>\n\t<dict>\n"
               "\t\t<key>NSExtensionPointIdentifier</key>\n\t\t<string>com.apple.widgetkit-extension</string>\n"
               "\t</dict>\n" + PLIST_TAIL)
    entitlements = (PLIST_HEAD +
                    "\t<key>com.apple.security.application-groups</key>\n\t<array>\n\t\t<string>" + group_id +
                    "</string>\n\t</array>\n" + PLIST_TAIL)
    app_entitlements = (PLIST_HEAD +
                        "\t<key>aps-environment</key>\n\t<string>development</string>\n"
                        "\t<key>com.apple.security.application-groups</key>\n\t<array>\n\t\t<string>" + group_id +
                        "</string>\n\t</array>\n" + PLIST_TAIL)
    if use_group:
        write_text(os.path.join(dirs[APP], f"{APP}.entitlements"), app_entitlements)
        write_text(os.path.join(dirs[WIDGET], f"{WIDGET}.entitlements"), entitlements)

    for folder, names in [(APP, APP_SOURCES + APP_RESOURCES), (WIDGET, WIDGET_SOURCES + WIDGET_RESOURCES), ("Shared", SHARED_SOURCES)]:
        for name in names:
            if not os.path.exists(os.path.join(dirs[folder], name)):
                sys.exit(f"missing file: {folder}/{name}")

    ids = {k: uid(k) for k in [
        "project", "target", "product", "group_root", "group_app", "group_widget", "group_shared",
        "sources_phase", "frameworks_phase", "resources_phase", "debug_proj", "release_proj",
        "debug_target", "release_target", "config_list_proj", "config_list_target", "app_ref",
        "w_target", "w_sources", "w_frameworks", "w_resources", "w_debug", "w_release", "w_config_list",
        "w_ref", "embed_phase", "embed_build", "proxy", "dependency", "pkg_ref", "pkg_prod", "pkg_build"]}

    def fid(folder, name):
        return uid(f"file_{folder}_{name}")

    def bid(folder, name, target):
        return uid(f"build_{folder}_{name}_{target}")

    L = []
    w = L.append
    w("// !$*UTF8*$!")
    w("{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 56;\n\tobjects = {")

    # ---- build files
    w("\n/* Begin PBXBuildFile section */")
    for name in APP_SOURCES:
        w(f"\t\t{bid(APP, name, 'app')} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid(APP, name)} /* {name} */; }};")
    for name in APP_RESOURCES:
        w(f"\t\t{bid(APP, name, 'app')} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {fid(APP, name)} /* {name} */; }};")
    for name in WIDGET_RESOURCES:
        w(f"\t\t{bid(WIDGET, name, 'w')} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {fid(WIDGET, name)} /* {name} */; }};")
    w(f"\t\t{uid('build_infoplist_strings')} /* InfoPlist.strings in Resources */ = {{isa = PBXBuildFile; fileRef = {uid('variant_infoplist')} /* InfoPlist.strings */; }};")
    for name in SHARED_SOURCES:
        w(f"\t\t{bid('Shared', name, 'app')} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid('Shared', name)} /* {name} */; }};")
        w(f"\t\t{bid('Shared', name, 'widget')} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid('Shared', name)} /* {name} */; }};")
    for name in WIDGET_SOURCES:
        w(f"\t\t{bid(WIDGET, name, 'widget')} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid(WIDGET, name)} /* {name} */; }};")
    w(f"\t\t{ids['pkg_build']} /* FirebaseAuth in Frameworks */ = {{isa = PBXBuildFile; productRef = {ids['pkg_prod']} /* FirebaseAuth */; }};")
    w(f"\t\t{ids['embed_build']} /* {WIDGET}.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; "
      f"fileRef = {ids['w_ref']} /* {WIDGET}.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};")
    w("/* End PBXBuildFile section */")

    # ---- container proxy + copy files + dependency
    w("\n/* Begin PBXContainerItemProxy section */")
    w(f"\t\t{ids['proxy']} /* PBXContainerItemProxy */ = {{isa = PBXContainerItemProxy; containerPortal = {ids['project']} /* Project object */; "
      f"proxyType = 1; remoteGlobalIDString = {ids['w_target']}; remoteInfo = {WIDGET}; }};")
    w("/* End PBXContainerItemProxy section */")

    w("\n/* Begin PBXCopyFilesBuildPhase section */")
    w(f"\t\t{ids['embed_phase']} /* Embed Foundation Extensions */ = {{isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; "
      f"dstPath = \"\"; dstSubfolderSpec = 13; files = ({ids['embed_build']} /* {WIDGET}.appex in Embed Foundation Extensions */, ); "
      f"name = \"Embed Foundation Extensions\"; runOnlyForDeploymentPostprocessing = 0; }};")
    w("/* End PBXCopyFilesBuildPhase section */")

    # ---- file references
    w("\n/* Begin PBXFileReference section */")
    w(f"\t\t{ids['app_ref']} /* {APP}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; "
      f"includeInIndex = 0; path = {APP}.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    w(f"\t\t{ids['w_ref']} /* {WIDGET}.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; "
      f"includeInIndex = 0; path = {WIDGET}.appex; sourceTree = BUILT_PRODUCTS_DIR; }};")
    for folder, names in [(APP, APP_SOURCES), (WIDGET, WIDGET_SOURCES), ("Shared", SHARED_SOURCES)]:
        for name in names:
            w(f"\t\t{fid(folder, name)} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
              f"path = {name}; sourceTree = \"<group>\"; }};")
    for name in APP_RESOURCES:
        w(f"\t\t{fid(APP, name)} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype(name)}; "
          f"path = {name}; sourceTree = \"<group>\"; }};")
    for name in WIDGET_RESOURCES:
        w(f"\t\t{fid(WIDGET, name)} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype(name)}; "
          f"path = {name}; sourceTree = \"<group>\"; }};")
    for lang in PERMISSION_TEXT:
        ql = '"' + lang + '"' if "-" in lang else lang
        w(f"\t\t{uid('file_infoplist_' + lang)} /* {lang} */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.strings; "
          f"name = {ql}; path = \"{lang}.lproj/InfoPlist.strings\"; sourceTree = \"<group>\"; }};")
    w("/* End PBXFileReference section */")

    # ---- frameworks phases
    w("\n/* Begin PBXFrameworksBuildPhase section */")
    for key in ("frameworks_phase", "w_frameworks"):
        fw = f"{ids['pkg_build']} /* FirebaseAuth in Frameworks */, " if key == "frameworks_phase" else ""
        w(f"\t\t{ids[key]} /* Frameworks */ = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; "
          f"files = ({fw}); runOnlyForDeploymentPostprocessing = 0; }};")
    w("/* End PBXFrameworksBuildPhase section */")

    # ---- groups
    w("\n/* Begin PBXGroup section */")
    w(f"\t\t{ids['group_root']} = {{isa = PBXGroup; children = ({ids['group_app']} /* {APP} */, {ids['group_widget']} /* {WIDGET} */, "
      f"{ids['group_shared']} /* Shared */, {ids['product']} /* Products */, ); sourceTree = \"<group>\"; }};")
    for key, folder, names in [("group_app", APP, APP_SOURCES + APP_RESOURCES), ("group_widget", WIDGET, WIDGET_SOURCES + WIDGET_RESOURCES),
                               ("group_shared", "Shared", SHARED_SOURCES)]:
        children = ", ".join(f"{fid(folder, n)} /* {n} */" for n in names)
        if key == "group_app":
            children += f", {uid('variant_infoplist')} /* InfoPlist.strings */"
        w(f"\t\t{ids[key]} /* {folder} */ = {{isa = PBXGroup; children = ({children}, ); path = {folder}; sourceTree = \"<group>\"; }};")
    w(f"\t\t{ids['product']} /* Products */ = {{isa = PBXGroup; children = ({ids['app_ref']} /* {APP}.app */, "
      f"{ids['w_ref']} /* {WIDGET}.appex */, ); name = Products; sourceTree = \"<group>\"; }};")
    w("/* End PBXGroup section */")
    w("\n/* Begin PBXVariantGroup section */")
    kids = ", ".join(f"{uid('file_infoplist_' + l)} /* {l} */" for l in PERMISSION_TEXT)
    w(f"\t\t{uid('variant_infoplist')} /* InfoPlist.strings */ = {{isa = PBXVariantGroup; children = ({kids}, ); "
      f"name = InfoPlist.strings; sourceTree = \"<group>\"; }};")
    w("/* End PBXVariantGroup section */")

    # ---- native targets
    w("\n/* Begin PBXNativeTarget section */")
    w(f"\t\t{ids['target']} /* {APP} */ = {{isa = PBXNativeTarget; buildConfigurationList = {ids['config_list_target']}; "
      f"buildPhases = ({ids['sources_phase']} /* Sources */, {ids['frameworks_phase']} /* Frameworks */, "
      f"{ids['resources_phase']} /* Resources */, {ids['embed_phase']} /* Embed Foundation Extensions */, ); buildRules = (); "
      f"dependencies = ({ids['dependency']} /* PBXTargetDependency */, ); name = {APP}; packageProductDependencies = ({ids['pkg_prod']} /* FirebaseAuth */, ); productName = {APP}; "
      f"productReference = {ids['app_ref']} /* {APP}.app */; productType = \"com.apple.product-type.application\"; }};")
    w(f"\t\t{ids['w_target']} /* {WIDGET} */ = {{isa = PBXNativeTarget; buildConfigurationList = {ids['w_config_list']}; "
      f"buildPhases = ({ids['w_sources']} /* Sources */, {ids['w_frameworks']} /* Frameworks */, {ids['w_resources']} /* Resources */, ); "
      f"buildRules = (); dependencies = (); name = {WIDGET}; productName = {WIDGET}; "
      f"productReference = {ids['w_ref']} /* {WIDGET}.appex */; productType = \"com.apple.product-type.app-extension\"; }};")
    w("/* End PBXNativeTarget section */")

    w("\n/* Begin PBXProject section */")
    w(f"\t\t{ids['project']} /* Project object */ = {{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = 1; "
      f"LastUpgradeCheck = 1600; }}; buildConfigurationList = {ids['config_list_proj']}; compatibilityVersion = \"Xcode 14.0\"; "
      f"developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, ja, \"zh-Hans\", ko, es, fr, Base, ); mainGroup = {ids['group_root']}; "
      f"productRefGroup = {ids['product']} /* Products */; projectDirPath = \"\"; projectRoot = \"\"; "
      f"packageReferences = ({ids['pkg_ref']} /* XCRemoteSwiftPackageReference \"firebase-ios-sdk\" */, ); "
      f"targets = ({ids['target']} /* {APP} */, {ids['w_target']} /* {WIDGET} */, ); }};")
    w("/* End PBXProject section */")

    # ---- resources phases
    w("\n/* Begin PBXResourcesBuildPhase section */")
    res_refs = ", ".join(f"{bid(APP, n, 'app')} /* {n} in Resources */" for n in APP_RESOURCES)
    res_refs += f", {uid('build_infoplist_strings')} /* InfoPlist.strings in Resources */"
    w(f"\t\t{ids['resources_phase']} /* Resources */ = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; "
      f"files = ({res_refs}, ); runOnlyForDeploymentPostprocessing = 0; }};")
    w(f"\t\t{ids['w_resources']} /* Resources */ = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; "
      f"files = ({', '.join(f'{bid(WIDGET, n, chr(119))} /* {n} in Resources */' for n in WIDGET_RESOURCES)}, ); runOnlyForDeploymentPostprocessing = 0; }};")
    w("/* End PBXResourcesBuildPhase section */")

    # ---- sources phases
    w("\n/* Begin PBXSourcesBuildPhase section */")
    app_refs = [f"{bid(APP, n, 'app')} /* {n} in Sources */" for n in APP_SOURCES] + \
               [f"{bid('Shared', n, 'app')} /* {n} in Sources */" for n in SHARED_SOURCES]
    w_refs = [f"{bid(WIDGET, n, 'widget')} /* {n} in Sources */" for n in WIDGET_SOURCES] + \
             [f"{bid('Shared', n, 'widget')} /* {n} in Sources */" for n in SHARED_SOURCES]
    w(f"\t\t{ids['sources_phase']} /* Sources */ = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; "
      f"files = ({', '.join(app_refs)}, ); runOnlyForDeploymentPostprocessing = 0; }};")
    w(f"\t\t{ids['w_sources']} /* Sources */ = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; "
      f"files = ({', '.join(w_refs)}, ); runOnlyForDeploymentPostprocessing = 0; }};")
    w("/* End PBXSourcesBuildPhase section */")

    w("\n/* Begin PBXTargetDependency section */")
    w(f"\t\t{ids['dependency']} /* PBXTargetDependency */ = {{isa = PBXTargetDependency; target = {ids['w_target']} /* {WIDGET} */; "
      f"targetProxy = {ids['proxy']} /* PBXContainerItemProxy */; }};")
    w("/* End PBXTargetDependency section */")

    # ---- build settings
    w("\n/* Begin XCBuildConfiguration section */")
    for key, name, debug in [("debug_proj", "Debug", True), ("release_proj", "Release", False)]:
        opt = ("SWIFT_OPTIMIZATION_LEVEL = \"-Onone\"; SWIFT_ACTIVE_COMPILATION_CONDITIONS = \"DEBUG\"; ") if debug else ""
        w(f"\t\t{ids[key]} /* {name} */ = {{isa = XCBuildConfiguration; buildSettings = {{ "
          f"ALWAYS_SEARCH_USER_PATHS = NO; CLANG_ENABLE_MODULES = YES; SWIFT_VERSION = 5.0; {opt}}}; name = {name}; }};")

    if use_group:
        # App Groups only work when the simulator build is signed (ad-hoc), so the entitlements get embedded.
        sim = ('"CODE_SIGNING_REQUIRED[sdk=iphonesimulator*]" = NO; "CODE_SIGNING_ALLOWED[sdk=iphonesimulator*]" = YES; '
               '"CODE_SIGN_IDENTITY[sdk=iphonesimulator*]" = "-"; ')
    else:
        sim = '"CODE_SIGNING_REQUIRED[sdk=iphonesimulator*]" = NO; "CODE_SIGNING_ALLOWED[sdk=iphonesimulator*]" = NO; '
    team_setting = f"DEVELOPMENT_TEAM = {team}; " if team else ""
    common = ("CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 3; GENERATE_INFOPLIST_FILE = YES; "
              "IPHONEOS_DEPLOYMENT_TARGET = 17.0; MARKETING_VERSION = 1.0; SUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\"; "
              "SUPPORTS_MACCATALYST = NO; SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = 1; ")
    app_settings = (common + team_setting + sim +
        f"INFOPLIST_FILE = {APP}/Info.plist; "
        "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES; INFOPLIST_KEY_UILaunchScreen_Generation = YES; "
        f"INFOPLIST_KEY_NSCameraUsageDescription = \"{CAMERA_REASON}\"; "
        "INFOPLIST_KEY_CFBundleDisplayName = Difframe; INFOPLIST_KEY_NSSupportsLiveActivities = YES; "
        f"INFOPLIST_KEY_NSContactsUsageDescription = \"{CONTACTS_REASON}\"; "
        f"INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = \"{LOCATION_REASON}\"; "
        f"INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription = \"{PHOTOS_REASON}\"; "
        f"INFOPLIST_KEY_NSMicrophoneUsageDescription = \"{MIC_REASON}\"; "
        "LD_RUNPATH_SEARCH_PATHS = (\"$(inherited)\", \"@executable_path/Frameworks\"); "
        f"PRODUCT_BUNDLE_IDENTIFIER = {bundle_id}; PRODUCT_NAME = \"$(TARGET_NAME)\"; "
        + (f"CODE_SIGN_ENTITLEMENTS = {APP}/{APP}.entitlements; " if use_group else ""))
    widget_settings = (common + team_setting + sim +
        f"INFOPLIST_FILE = {WIDGET}/Info.plist; INFOPLIST_KEY_CFBundleDisplayName = Difframe; "
        "LD_RUNPATH_SEARCH_PATHS = (\"$(inherited)\", \"@executable_path/Frameworks\", \"@executable_path/../../Frameworks\"); "
        f"PRODUCT_BUNDLE_IDENTIFIER = {widget_bundle_id}; PRODUCT_NAME = \"$(TARGET_NAME)\"; SKIP_INSTALL = YES; "
        + (f"CODE_SIGN_ENTITLEMENTS = {WIDGET}/{WIDGET}.entitlements; " if use_group else ""))
    for key, name in [("debug_target", "Debug"), ("release_target", "Release")]:
        w(f"\t\t{ids[key]} /* {name} */ = {{isa = XCBuildConfiguration; buildSettings = {{ {app_settings}}}; name = {name}; }};")
    for key, name in [("w_debug", "Debug"), ("w_release", "Release")]:
        w(f"\t\t{ids[key]} /* {name} */ = {{isa = XCBuildConfiguration; buildSettings = {{ {widget_settings}}}; name = {name}; }};")
    w("/* End XCBuildConfiguration section */")

    w("\n/* Begin XCRemoteSwiftPackageReference section */")
    w(f"\t\t{ids['pkg_ref']} /* XCRemoteSwiftPackageReference \"firebase-ios-sdk\" */ = {{isa = XCRemoteSwiftPackageReference; "
      f"repositoryURL = \"{FIREBASE_URL}\"; requirement = {{kind = upToNextMajorVersion; minimumVersion = 11.0.0; }}; }};")
    w("/* End XCRemoteSwiftPackageReference section */")
    w("\n/* Begin XCSwiftPackageProductDependency section */")
    w(f"\t\t{ids['pkg_prod']} /* FirebaseAuth */ = {{isa = XCSwiftPackageProductDependency; package = {ids['pkg_ref']} /* XCRemoteSwiftPackageReference \"firebase-ios-sdk\" */; productName = FirebaseAuth; }};")
    w("/* End XCSwiftPackageProductDependency section */")

    w("\n/* Begin XCConfigurationList section */")
    w(f"\t\t{ids['config_list_proj']} /* Build configuration list for PBXProject */ = {{isa = XCConfigurationList; "
      f"buildConfigurations = ({ids['debug_proj']} /* Debug */, {ids['release_proj']} /* Release */, ); "
      f"defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};")
    w(f"\t\t{ids['config_list_target']} /* Build configuration list for PBXNativeTarget */ = {{isa = XCConfigurationList; "
      f"buildConfigurations = ({ids['debug_target']} /* Debug */, {ids['release_target']} /* Release */, ); "
      f"defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};")
    w(f"\t\t{ids['w_config_list']} /* Build configuration list for PBXNativeTarget */ = {{isa = XCConfigurationList; "
      f"buildConfigurations = ({ids['w_debug']} /* Debug */, {ids['w_release']} /* Release */, ); "
      f"defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};")
    w("/* End XCConfigurationList section */")

    w("\t};")
    w(f"\trootObject = {ids['project']} /* Project object */;")
    w("}")

    bundle = os.path.join(root, f"{APP}.xcodeproj")
    os.makedirs(bundle, exist_ok=True)
    out = os.path.join(bundle, "project.pbxproj")
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")
    print("wrote", out)
    print(f"bundle id: {bundle_id} (widget: {widget_bundle_id}); team: {team or '(none)'}; app group: {group_id if use_group else 'off'}")


if __name__ == "__main__":
    main()
