#!/usr/bin/env python3
"""Write CainerVision.xcodeproj from the files on disk.

The project file is committed. Run this only after adding or removing a source file.
"""

from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "CainerVision"
PROJECT = ROOT / "CainerVision.xcodeproj"


def pid(text: str) -> str:
    return hashlib.sha1(text.encode()).hexdigest()[:24].upper()


def file_type(path: Path) -> str:
    if path.suffix == ".swift":
        return "sourcecode.swift"
    if path.name == "Info.plist":
        return "text.plist.xml"
    if path.suffix == ".xcprivacy":
        return "text.xml"
    if path.suffix == ".usdz":
        # Copy as a plain file so Xcode does not try to recompile the sample USDZ.
        return "file"
    if path.suffix == ".md":
        return "net.daringfireball.markdown"
    if path.name == "LICENSE":
        return "text"
    return "file"


def main() -> None:
    swift_files = sorted(SOURCE.rglob("*.swift"))
    usdz_files = sorted((SOURCE / "Resources" / "Samples").glob("*.usdz"))
    resources = [SOURCE / "Assets.xcassets", SOURCE / "PrivacyInfo.xcprivacy", *usdz_files]
    extra_root = [ROOT / "README.md", ROOT / "LICENSE"]

    target_id = pid("target:CainerVision")
    project_id = pid("project:CainerVision")
    product_id = pid("product:CainerVision.app")
    main_group = pid("group:main")
    product_group = pid("group:Products")
    source_group = pid("group:CainerVision")
    sources_phase = pid("phase:sources")
    resources_phase = pid("phase:resources")
    frameworks_phase = pid("phase:frameworks")
    debug_id = pid("config:project:Debug")
    release_id = pid("config:project:Release")
    target_debug = pid("config:target:Debug")
    target_release = pid("config:target:Release")
    config_list_project = pid("list:project")
    config_list_target = pid("list:target")

    groups: dict[Path, str] = {SOURCE: source_group}
    for folder in sorted({path.parent for path in [*swift_files, *usdz_files]}):
        current = folder
        while current != SOURCE and SOURCE in current.parents:
            groups.setdefault(current, pid(f"group:{current.relative_to(ROOT).as_posix()}"))
            current = current.parent

    file_refs: dict[Path, str] = {}
    for path in [*swift_files, *resources, *extra_root, SOURCE / "Info.plist"]:
        file_refs[path] = pid(f"file:{path.relative_to(ROOT).as_posix()}")

    build_files: dict[Path, str] = {}
    for path in [*swift_files, *resources]:
        build_files[path] = pid(f"build:{path.relative_to(ROOT).as_posix()}")

    def rel_to_parent(path: Path) -> str:
        parent = path.parent
        if parent == ROOT:
            return path.name
        return path.name

    lines: list[str] = []
    w = lines.append
    w("// !$*UTF8*$!")
    w("{")
    w("\tarchiveVersion = 1;")
    w("\tclasses = {")
    w("\t};")
    w("\tobjectVersion = 56;")
    w("\tobjects = {")
    w("")
    w("/* Begin PBXBuildFile section */")
    for path in [*swift_files, *resources]:
        w(f"\t\t{build_files[path]} /* {path.name} in {'Sources' if path.suffix == '.swift' else 'Resources'} */ = {{isa = PBXBuildFile; fileRef = {file_refs[path]} /* {path.name} */; }};")
    w("/* End PBXBuildFile section */")
    w("")
    w("/* Begin PBXFileReference section */")
    w(f"\t\t{product_id} /* CainerVision.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = CainerVision.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    for path, ref in file_refs.items():
        kind = "folder.assetcatalog" if path.suffix == ".xcassets" else file_type(path)
        name = path.name.replace('"', "")
        w(f"\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {kind}; path = {name}; sourceTree = \"<group>\"; }};")
    w("/* End PBXFileReference section */")
    w("")
    w("/* Begin PBXFrameworksBuildPhase section */")
    w(f"\t\t{frameworks_phase} /* Frameworks */ = {{")
    w("\t\t\tisa = PBXFrameworksBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXFrameworksBuildPhase section */")
    w("")
    w("/* Begin PBXGroup section */")

    def children_of(folder: Path) -> list[str]:
        entries: list[tuple[str, str]] = []
        child_folders = sorted({p for p, gid in groups.items() if p.parent == folder}, key=lambda p: p.name)
        for child in child_folders:
            entries.append((child.name, f"{groups[child]} /* {child.name} */"))
        child_files = sorted((p for p in file_refs if p.parent == folder), key=lambda p: p.name)
        for child in child_files:
            entries.append((child.name, f"{file_refs[child]} /* {child.name} */"))
        return [ref for _, ref in entries]

    for folder, gid in sorted(groups.items(), key=lambda item: item[0].as_posix()):
        name = "CainerVision" if folder == SOURCE else folder.name
        path = "CainerVision" if folder == SOURCE else folder.name
        w(f"\t\t{gid} /* {name} */ = {{")
        w("\t\t\tisa = PBXGroup;")
        w("\t\t\tchildren = (")
        for child in children_of(folder):
            w(f"\t\t\t\t{child},")
        w("\t\t\t);")
        w(f"\t\t\tpath = {path};")
        w('\t\t\tsourceTree = "<group>";')
        w("\t\t};")

    w(f"\t\t{product_group} /* Products */ = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w(f"\t\t\t\t{product_id} /* CainerVision.app */,")
    w("\t\t\t);")
    w("\t\t\tname = Products;")
    w('\t\t\tsourceTree = "<group>";')
    w("\t\t};")
    w(f"\t\t{main_group} = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w(f"\t\t\t\t{source_group} /* CainerVision */,")
    w(f"\t\t\t\t{file_refs[ROOT / 'README.md']} /* README.md */,")
    w(f"\t\t\t\t{file_refs[ROOT / 'LICENSE']} /* LICENSE */,")
    w(f"\t\t\t\t{product_group} /* Products */,")
    w("\t\t\t);")
    w('\t\t\tsourceTree = "<group>";')
    w("\t\t};")
    w("/* End PBXGroup section */")
    w("")
    w("/* Begin PBXNativeTarget section */")
    w(f"\t\t{target_id} /* CainerVision */ = {{")
    w("\t\t\tisa = PBXNativeTarget;")
    w(f"\t\t\tbuildConfigurationList = {config_list_target} /* Build configuration list for PBXNativeTarget \"CainerVision\" */;")
    w("\t\t\tbuildPhases = (")
    w(f"\t\t\t\t{sources_phase} /* Sources */,")
    w(f"\t\t\t\t{frameworks_phase} /* Frameworks */,")
    w(f"\t\t\t\t{resources_phase} /* Resources */,")
    w("\t\t\t);")
    w("\t\t\tbuildRules = (")
    w("\t\t\t);")
    w("\t\t\tdependencies = (")
    w("\t\t\t);")
    w("\t\t\tname = CainerVision;")
    w(f"\t\t\tproductName = CainerVision;")
    w(f"\t\t\tproductReference = {product_id} /* CainerVision.app */;")
    w("\t\t\tproductType = \"com.apple.product-type.application\";")
    w("\t\t};")
    w("/* End PBXNativeTarget section */")
    w("")
    w("/* Begin PBXProject section */")
    w(f"\t\t{project_id} /* Project object */ = {{")
    w("\t\t\tisa = PBXProject;")
    w("\t\t\tattributes = {")
    w("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    w("\t\t\t\tLastUpgradeCheck = 1500;")
    w("\t\t\t\tORGANIZATIONNAME = Cainering;")
    w("\t\t\t\tTargetAttributes = {")
    w(f"\t\t\t\t\t{target_id} = {{")
    w("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
    w("\t\t\t\t\t};")
    w("\t\t\t\t};")
    w("\t\t\t};")
    w(f"\t\t\tbuildConfigurationList = {config_list_project} /* Build configuration list for PBXProject \"CainerVision\" */;")
    w('\t\t\tcompatibilityVersion = "Xcode 14.0";')
    w("\t\t\tdevelopmentRegion = en;")
    w("\t\t\thasScannedForEncodings = 0;")
    w("\t\t\tknownRegions = (")
    w("\t\t\t\ten,")
    w("\t\t\t\tBase,")
    w("\t\t\t);")
    w(f"\t\t\tmainGroup = {main_group};")
    w(f"\t\t\tproductRefGroup = {product_group} /* Products */;")
    w('\t\t\tprojectDirPath = "";')
    w('\t\t\tprojectRoot = "";')
    w("\t\t\ttargets = (")
    w(f"\t\t\t\t{target_id} /* CainerVision */,")
    w("\t\t\t);")
    w("\t\t};")
    w("/* End PBXProject section */")
    w("")
    w("/* Begin PBXResourcesBuildPhase section */")
    w(f"\t\t{resources_phase} /* Resources */ = {{")
    w("\t\t\tisa = PBXResourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    for path in resources:
        w(f"\t\t\t\t{build_files[path]} /* {path.name} in Resources */,")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXResourcesBuildPhase section */")
    w("")
    w("/* Begin PBXSourcesBuildPhase section */")
    w(f"\t\t{sources_phase} /* Sources */ = {{")
    w("\t\t\tisa = PBXSourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    for path in swift_files:
        w(f"\t\t\t\t{build_files[path]} /* {path.name} in Sources */,")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXSourcesBuildPhase section */")
    w("")
    w("/* Begin XCBuildConfiguration section */")
    w(project_config(debug_id, debug=True))
    w(project_config(release_id, debug=False))
    w(target_config(target_debug, debug=True))
    w(target_config(target_release, debug=False))
    w("/* End XCBuildConfiguration section */")
    w("")
    w("/* Begin XCConfigurationList section */")
    w(f"\t\t{config_list_project} /* Build configuration list for PBXProject \"CainerVision\" */ = {{")
    w("\t\t\tisa = XCConfigurationList;")
    w("\t\t\tbuildConfigurations = (")
    w(f"\t\t\t\t{debug_id} /* Debug */,")
    w(f"\t\t\t\t{release_id} /* Release */,")
    w("\t\t\t);")
    w("\t\t\tdefaultConfigurationIsVisible = 0;")
    w("\t\t\tdefaultConfigurationName = Release;")
    w("\t\t};")
    w(f"\t\t{config_list_target} /* Build configuration list for PBXNativeTarget \"CainerVision\" */ = {{")
    w("\t\t\tisa = XCConfigurationList;")
    w("\t\t\tbuildConfigurations = (")
    w(f"\t\t\t\t{target_debug} /* Debug */,")
    w(f"\t\t\t\t{target_release} /* Release */,")
    w("\t\t\t);")
    w("\t\t\tdefaultConfigurationIsVisible = 0;")
    w("\t\t\tdefaultConfigurationName = Release;")
    w("\t\t};")
    w("/* End XCConfigurationList section */")
    w("\t};")
    w(f"\trootObject = {project_id} /* Project object */;")
    w("}")
    w("")

    pbx = PROJECT / "project.pbxproj"
    pbx.write_text("\n".join(lines), encoding="utf-8")
    write_scheme(target_id)
    write_workspace()
    print(f"wrote {pbx.relative_to(ROOT)}")
    print(f"sources: {len(swift_files)}  resources: {len(resources)}")


def project_config(config_id: str, debug: bool) -> str:
    name = "Debug" if debug else "Release"
    debug_only = ""
    if debug:
        debug_only = """
\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\tENABLE_TESTABILITY = YES;
\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t"DEBUG=1",
\t\t\t\t"$(inherited)",
\t\t\t);
\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";"""
    else:
        debug_only = """
\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\tVALIDATE_PRODUCT = YES;"""
    return f"""\t\t{config_id} /* {name} */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_COMMA = YES;
\t\t\t\tCLANG_WARN_CONSTANT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;
\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;
\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;
\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
\t\t\t\tCLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
\t\t\t\tCLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
\t\t\t\tCLANG_WARN_STRICT_PROTOTYPES = YES;
\t\t\t\tCLANG_WARN_SUSPICIOUS_MOVE = YES;
\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;
\t\t\t\tCLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
\t\t\t\tCOPY_PHASE_STRIP = {"NO" if debug else "YES"};
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES;
\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;
\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tSDKROOT = iphoneos;{debug_only}
\t\t\t}};
\t\t\tname = {name};
\t\t}};"""


def target_config(config_id: str, debug: bool) -> str:
    name = "Debug" if debug else "Release"
    return f"""\t\t{config_id} /* {name} */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = CainerVision/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.cainering.CainerVision;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSUPPORTS_MACCATALYST = NO;
\t\t\t\tSUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;
\t\t\t\tSUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = NO;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 1;
\t\t\t}};
\t\t\tname = {name};
\t\t}};"""


def write_scheme(target_id: str) -> None:
    scheme_dir = PROJECT / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    ref = f"""<BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target_id}"
               BuildableName = "CainerVision.app"
               BlueprintName = "CainerVision"
               ReferencedContainer = "container:CainerVision.xcodeproj">
            </BuildableReference>"""
    text = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            {ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {ref}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {ref}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
    (scheme_dir / "CainerVision.xcscheme").write_text(text, encoding="utf-8")


def write_workspace() -> None:
    workspace = PROJECT / "project.xcworkspace"
    workspace.mkdir(parents=True, exist_ok=True)
    (workspace / "contents.xcworkspacedata").write_text(
        """<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
""",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
