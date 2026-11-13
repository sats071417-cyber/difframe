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

APP_SOURCES = ["HitokomaApp.swift", "ContentView.swift", "TodayView.swift",
               "FriendsView.swift", "WorldMapView.swift",
               "SamplePosts.swift", "PostStore.swift", "CalendarView.swift", "NotificationScheduler.swift",
               "FriendCode.swift", "PromptArt.swift", "PromptVerifier.swift", "ProfileView.swift",
               "Achievements.swift", "Theme.swift", "WorldView.swift", "WorldSamples.swift",
               "CaptureFlow.swift", "WidgetBridge.swift", "OnboardingView.swift", "PromptCatalog.swift",
               "Account.swift", "SignUpView.swift", "ContactsView.swift", "Localization.swift", "LocalizedEN.swift", "LocalizedZH.swift", "LocalizedKO.swift", "LocalizedES.swift", "TimelineScreen.swift", "Social.swift", "CityLocator.swift", "GlobeView.swift", "SettingsView.swift", "ShareCard.swift", "CloudConfig.swift", "Cloud.swift", "CloudViews.swift", "FriendList.swift", "CloudInbox.swift", "InboxViews.swift", "ChatMedia.swift", "BackgroundSync.swift"]
def ftype(name):
    return 'folder.assetcatalog' if name.endswith('.xcassets') else 'text.json'


APP_RESOURCES = ["sample_posts.json", "Assets.xcassets"]
WIDGET_SOURCES = ["HitokomaWidget.swift"]
SHARED_SOURCES = ["WidgetSnapshot.swift", "AppGroup.swift"]
LOCATION_REASON = "地図であなたのいる場所を示したり、投稿に都市の名前（例：東京）をつけるために使います。正確な位置は送信しません。"
CONTACTS_REASON = "友達に招待リンクを送る相手を選ぶために使います。連絡先は端末の外へ送りません。"
CAMERA_REASON = "お題に合わせて、その場で写真を撮るために使います。"


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
               "\t\t\t<key>CFBundleURLSchemes</key>\n\t\t\t<array>\n\t\t\t\t<string>hitokoma</string>\n\t\t\t</array>\n"
               "\t\t</dict>\n\t</array>\n"
               "\t<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>fetch</string>\n\t</array>\n"
               "\t<key>BGTaskSchedulerPermittedIdentifiers</key>\n\t<array>\n\t\t<string>" + bundle_id + ".refresh</string>\n\t</array>\n" + PLIST_TAIL)
    write_text(os.path.join(dirs[WIDGET], "Info.plist"),
               PLIST_HEAD +
               "\t<key>NSExtension</key>\n\t<dict>\n"
               "\t\t<key>NSExtensionPointIdentifier</key>\n\t\t<string>com.apple.widgetkit-extension</string>\n"
               "\t</dict>\n" + PLIST_TAIL)
    entitlements = (PLIST_HEAD +
                    "\t<key>com.apple.security.application-groups</key>\n\t<array>\n\t\t<string>" + group_id +
                    "</string>\n\t</array>\n" + PLIST_TAIL)
    if use_group:
        write_text(os.path.join(dirs[APP], f"{APP}.entitlements"), entitlements)
        write_text(os.path.join(dirs[WIDGET], f"{WIDGET}.entitlements"), entitlements)

    for folder, names in [(APP, APP_SOURCES + APP_RESOURCES), (WIDGET, WIDGET_SOURCES), ("Shared", SHARED_SOURCES)]:
        for name in names:
            if not os.path.exists(os.path.join(dirs[folder], name)):
                sys.exit(f"missing file: {folder}/{name}")

    ids = {k: uid(k) for k in [
        "project", "target", "product", "group_root", "group_app", "group_widget", "group_shared",
        "sources_phase", "frameworks_phase", "resources_phase", "debug_proj", "release_proj",
        "debug_target", "release_target", "config_list_proj", "config_list_target", "app_ref",
        "w_target", "w_sources", "w_frameworks", "w_resources", "w_debug", "w_release", "w_config_list",
        "w_ref", "embed_phase", "embed_build", "proxy", "dependency"]}

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
    for name in SHARED_SOURCES:
        w(f"\t\t{bid('Shared', name, 'app')} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid('Shared', name)} /* {name} */; }};")
        w(f"\t\t{bid('Shared', name, 'widget')} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid('Shared', name)} /* {name} */; }};")
    for name in WIDGET_SOURCES:
        w(f"\t\t{bid(WIDGET, name, 'widget')} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid(WIDGET, name)} /* {name} */; }};")
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
    w("/* End PBXFileReference section */")

    # ---- frameworks phases
    w("\n/* Begin PBXFrameworksBuildPhase section */")
    for key in ("frameworks_phase", "w_frameworks"):
        w(f"\t\t{ids[key]} /* Frameworks */ = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; "
          f"files = (); runOnlyForDeploymentPostprocessing = 0; }};")
    w("/* End PBXFrameworksBuildPhase section */")

    # ---- groups
    w("\n/* Begin PBXGroup section */")
    w(f"\t\t{ids['group_root']} = {{isa = PBXGroup; children = ({ids['group_app']} /* {APP} */, {ids['group_widget']} /* {WIDGET} */, "
      f"{ids['group_shared']} /* Shared */, {ids['product']} /* Products */, ); sourceTree = \"<group>\"; }};")
    for key, folder, names in [("group_app", APP, APP_SOURCES + APP_RESOURCES), ("group_widget", WIDGET, WIDGET_SOURCES),
                               ("group_shared", "Shared", SHARED_SOURCES)]:
        children = ", ".join(f"{fid(folder, n)} /* {n} */" for n in names)
        w(f"\t\t{ids[key]} /* {folder} */ = {{isa = PBXGroup; children = ({children}, ); path = {folder}; sourceTree = \"<group>\"; }};")
    w(f"\t\t{ids['product']} /* Products */ = {{isa = PBXGroup; children = ({ids['app_ref']} /* {APP}.app */, "
      f"{ids['w_ref']} /* {WIDGET}.appex */, ); name = Products; sourceTree = \"<group>\"; }};")
    w("/* End PBXGroup section */")

    # ---- native targets
    w("\n/* Begin PBXNativeTarget section */")
    w(f"\t\t{ids['target']} /* {APP} */ = {{isa = PBXNativeTarget; buildConfigurationList = {ids['config_list_target']}; "
      f"buildPhases = ({ids['sources_phase']} /* Sources */, {ids['frameworks_phase']} /* Frameworks */, "
      f"{ids['resources_phase']} /* Resources */, {ids['embed_phase']} /* Embed Foundation Extensions */, ); buildRules = (); "
      f"dependencies = ({ids['dependency']} /* PBXTargetDependency */, ); name = {APP}; productName = {APP}; "
      f"productReference = {ids['app_ref']} /* {APP}.app */; productType = \"com.apple.product-type.application\"; }};")
    w(f"\t\t{ids['w_target']} /* {WIDGET} */ = {{isa = PBXNativeTarget; buildConfigurationList = {ids['w_config_list']}; "
      f"buildPhases = ({ids['w_sources']} /* Sources */, {ids['w_frameworks']} /* Frameworks */, {ids['w_resources']} /* Resources */, ); "
      f"buildRules = (); dependencies = (); name = {WIDGET}; productName = {WIDGET}; "
      f"productReference = {ids['w_ref']} /* {WIDGET}.appex */; productType = \"com.apple.product-type.app-extension\"; }};")
    w("/* End PBXNativeTarget section */")

    w("\n/* Begin PBXProject section */")
    w(f"\t\t{ids['project']} /* Project object */ = {{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = 1; "
      f"LastUpgradeCheck = 1600; }}; buildConfigurationList = {ids['config_list_proj']}; compatibilityVersion = \"Xcode 14.0\"; "
      f"developmentRegion = ja; hasScannedForEncodings = 0; knownRegions = (ja, en, Base, ); mainGroup = {ids['group_root']}; "
      f"productRefGroup = {ids['product']} /* Products */; projectDirPath = \"\"; projectRoot = \"\"; "
      f"targets = ({ids['target']} /* {APP} */, {ids['w_target']} /* {WIDGET} */, ); }};")
    w("/* End PBXProject section */")

    # ---- resources phases
    w("\n/* Begin PBXResourcesBuildPhase section */")
    res_refs = ", ".join(f"{bid(APP, n, 'app')} /* {n} in Resources */" for n in APP_RESOURCES)
    w(f"\t\t{ids['resources_phase']} /* Resources */ = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; "
      f"files = ({res_refs}, ); runOnlyForDeploymentPostprocessing = 0; }};")
    w(f"\t\t{ids['w_resources']} /* Resources */ = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; "
      f"files = (); runOnlyForDeploymentPostprocessing = 0; }};")
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
        opt = "SWIFT_OPTIMIZATION_LEVEL = \"-Onone\"; " if debug else ""
        w(f"\t\t{ids[key]} /* {name} */ = {{isa = XCBuildConfiguration; buildSettings = {{ "
          f"ALWAYS_SEARCH_USER_PATHS = NO; CLANG_ENABLE_MODULES = YES; SWIFT_VERSION = 5.0; {opt}}}; name = {name}; }};")

    sim = '"CODE_SIGNING_REQUIRED[sdk=iphonesimulator*]" = NO; "CODE_SIGNING_ALLOWED[sdk=iphonesimulator*]" = NO; '
    team_setting = f"DEVELOPMENT_TEAM = {team}; " if team else ""
    common = ("CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 1; GENERATE_INFOPLIST_FILE = YES; "
              "IPHONEOS_DEPLOYMENT_TARGET = 17.0; MARKETING_VERSION = 1.0; SUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\"; "
              "SUPPORTS_MACCATALYST = NO; SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = 1; ")
    app_settings = (common + team_setting + sim +
        f"INFOPLIST_FILE = {APP}/Info.plist; "
        "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES; INFOPLIST_KEY_UILaunchScreen_Generation = YES; "
        f"INFOPLIST_KEY_NSCameraUsageDescription = \"{CAMERA_REASON}\"; "
        "INFOPLIST_KEY_CFBundleDisplayName = Difframe; "
        f"INFOPLIST_KEY_NSContactsUsageDescription = \"{CONTACTS_REASON}\"; "
        f"INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = \"{LOCATION_REASON}\"; "
        f"INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription = \"自分の投稿を、写真アプリに保存するために使います。\"; "
        f"INFOPLIST_KEY_NSMicrophoneUsageDescription = \"ボイスメッセージを録音するために使います。\"; "
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
