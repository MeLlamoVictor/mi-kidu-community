#!/usr/bin/env python3
"""Generate the Mi Kidu Xcode project without third-party dependencies.

The project and schemes are deterministic. Swift source files are discovered
only under the four platform directories. Package.swift is owned separately
and must be added at this directory's root by the integrator.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT_NAME = "MiKidu"

TARGETS = {
    "mac": {
        "name": "Mi Kidu Mac",
        "product": "MiKiduMac.app",
        "product_type": "com.apple.product-type.application",
        "file_type": "wrapper.application",
        "source_dir": "Apps/Mac",
        "group": "mac",
        "bundle_id": "org.example.mikidu.community",
        "sdk": "macosx",
        "platforms": "macosx",
        "family": None,
        "deployment_setting": "MACOSX_DEPLOYMENT_TARGET",
        "deployment": "15.0",
        "info": "Config/Info-Mac.plist",
        "entitlements": "Config/MiKidu-Mac.entitlements",
        "products": ["MiKiduCore", "MiKiduShell", "MiKiduWidgetWatch", "MiKiduPresentation"],
        "skip_install": "NO",
    },
    "ios": {
        "name": "Mi Kidu iPhone",
        "product": "MiKidu.app",
        "product_type": "com.apple.product-type.application",
        "file_type": "wrapper.application",
        "source_dir": "Apps/iOS",
        "group": "ios",
        "bundle_id": "org.example.mikidu.community",
        "sdk": "iphoneos",
        "platforms": "iphoneos iphonesimulator",
        "family": "1,2",
        "deployment_setting": "IPHONEOS_DEPLOYMENT_TARGET",
        "deployment": "18.0",
        "info": "Config/Info-iOS.plist",
        "entitlements": "Config/MiKidu-iOS.entitlements",
        "products": ["MiKiduCore", "MiKiduShell", "MiKiduWidgetWatch", "MiKiduPresentation"],
        "skip_install": "NO",
    },
    "widget": {
        "name": "Mi Kidu Widget",
        "product": "MiKiduWidget.appex",
        "product_type": "com.apple.product-type.app-extension",
        "file_type": "wrapper.app-extension",
        "source_dir": "Apps/Widget",
        "group": "widget",
        "bundle_id": "org.example.mikidu.community.widget",
        "sdk": "iphoneos",
        "platforms": "iphoneos iphonesimulator",
        "family": "1,2",
        "deployment_setting": "IPHONEOS_DEPLOYMENT_TARGET",
        "deployment": "18.0",
        "info": "Config/Info-Widget.plist",
        "entitlements": "Config/MiKidu-Widget.entitlements",
        "products": ["MiKiduCore", "MiKiduWidgetWatch", "MiKiduPresentation"],
        "skip_install": "YES",
    },
    "watch": {
        "name": "Mi Kidu Watch",
        "product": "MiKiduWatch.app",
        "product_type": "com.apple.product-type.application",
        "file_type": "wrapper.application",
        "source_dir": "Apps/Watch",
        "group": "watch",
        "bundle_id": "org.example.mikidu.community.watch",
        "sdk": "watchos",
        "platforms": "watchos watchsimulator",
        "family": "4",
        "deployment_setting": "WATCHOS_DEPLOYMENT_TARGET",
        "deployment": "11.0",
        "info": "Config/Info-Watch.plist",
        "entitlements": "Config/MiKidu-Watch.entitlements",
        "products": ["MiKiduCore", "MiKiduShell", "MiKiduWidgetWatch", "MiKiduPresentation"],
        "skip_install": "YES",
    },
}

SHARED_DIR = "Apps/Shared"
WIDGET_SHARED_SOURCES = {"KiduLocalEnvironment.swift"}

PRODUCTS = ["MiKiduCore", "MiKiduShell", "MiKiduWidgetWatch", "MiKiduPresentation"]


class Project:
    def __init__(self) -> None:
        self.objects: dict[str, str] = {}
        self.object_ids: dict[str, str] = {}

    def oid(self, key: str) -> str:
        if key not in self.object_ids:
            value = hashlib.sha256((PROJECT_NAME + ":" + key).encode()).hexdigest()[:24].upper()
            if value in self.object_ids.values():
                raise RuntimeError(f"Stable Xcode ID collision for {key}")
            self.object_ids[key] = value
        return self.object_ids[key]

    def add(self, key: str, body: str) -> str:
        object_id = self.oid(key)
        if object_id in self.objects:
            raise RuntimeError(f"Duplicate Xcode object {key}")
        self.objects[object_id] = body
        return object_id


def q(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def plist_array(values: list[str]) -> str:
    if not values:
        return "()"
    return "(\n" + "".join(f"\t\t\t\t{q(value)},\n" for value in values) + "\t\t\t)"


def setting(name: str, value: str) -> str:
    return f"\t\t\t\t{name} = {q(value)};\n"


def discover_files(directory: Path) -> tuple[list[Path], list[Path]]:
    """Return Swift source and resource paths, sorted by POSIX relative path."""
    sources: list[Path] = []
    resources: list[Path] = []
    if not directory.exists():
        return sources, resources

    for path in directory.rglob("*"):
        if any(part.startswith(".") for part in path.relative_to(directory).parts):
            continue
        if path.is_file() and path.suffix == ".swift":
            sources.append(path)
        elif path.is_dir() and path.suffix == ".xcassets":
            resources.append(path)
        elif path.is_file() and path.suffix in {".json", ".strings", ".stringsdict", ".png", ".jpg", ".jpeg", ".pdf", ".colorset"}:
            resources.append(path)

    key = lambda item: item.relative_to(ROOT).as_posix()
    return sorted(sources, key=key), sorted(resources, key=key)


def file_type(path: Path) -> str:
    if path.suffix == ".swift":
        return "sourcecode.swift"
    if path.suffix == ".xcassets":
        return "folder.assetcatalog"
    return {
        ".json": "text.json",
        ".strings": "text.plist.strings",
        ".stringsdict": "text.plist.stringsdict",
        ".png": "image.png",
        ".jpg": "image.jpeg",
        ".jpeg": "image.jpeg",
        ".pdf": "image.pdf",
        ".colorset": "folder",
    }.get(path.suffix, "file")


def add_file_reference(project: Project, key: str, path: Path, group_relative: bool) -> str:
    name = path.name
    path_value = path.relative_to(ROOT).as_posix() if not group_relative else name
    source_tree = "<group>" if group_relative else "SOURCE_ROOT"
    return project.add(
        f"file:{key}",
        "\n".join(
            [
                "isa = PBXFileReference;",
                f"lastKnownFileType = {q(file_type(path))};",
                f"path = {q(path_value)};",
                f"sourceTree = {q(source_tree)};",
            ]
        ),
    )


def add_build_file(project: Project, key: str, file_ref: str, attributes: list[str] | None = None) -> str:
    body = ["isa = PBXBuildFile;", f"fileRef = {file_ref};"]
    if attributes:
        body.append(f"settings = {{ ATTRIBUTES = {plist_array(attributes)}; }};")
    return project.add(f"buildfile:{key}", "\n".join(body))


def add_package_build_file(project: Project, key: str, product_ref: str) -> str:
    return project.add(
        f"buildfile:{key}",
        "\n".join(["isa = PBXBuildFile;", f"productRef = {product_ref};"]),
    )


def config_settings(config: dict[str, str]) -> str:
    return "".join(setting(name, value) for name, value in config.items())


def target_settings(target: dict[str, object], configuration: str) -> dict[str, str]:
    debug = configuration == "Debug"
    values = {
        "CODE_SIGN_ENTITLEMENTS": str(target["entitlements"]),
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": "$(MIKIDU_DEVELOPMENT_TEAM)",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": str(target["info"]),
        "MARKETING_VERSION": "0.1",
        "PRODUCT_BUNDLE_IDENTIFIER": str(target["bundle_id"]),
        "PRODUCT_NAME": str(target["product"]).rsplit(".", 1)[0],
        "SDKROOT": str(target["sdk"]),
        "SKIP_INSTALL": str(target["skip_install"]),
        "SUPPORTED_PLATFORMS": str(target["platforms"]),
        str(target["deployment_setting"]): str(target["deployment"]),
        "SWIFT_VERSION": "6.0",
    }
    if target["family"] is not None:
        values["TARGETED_DEVICE_FAMILY"] = str(target["family"])
    if target["group"] == "widget":
        values["APPLICATION_EXTENSION_API_ONLY"] = "YES"
        values["LD_RUNPATH_SEARCH_PATHS"] = "$(inherited) @executable_path/../../Frameworks"
    elif target["group"] in {"ios", "watch"}:
        values["LD_RUNPATH_SEARCH_PATHS"] = "$(inherited) @executable_path/Frameworks"
    values["ONLY_ACTIVE_ARCH"] = "YES" if debug else "NO"
    values["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone" if debug else "-O"
    values["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG $(inherited)" if debug else "$(inherited)"
    return values


def add_build_configuration(
    project: Project,
    key: str,
    name: str,
    settings_map: dict[str, str],
    base_config_ref: str | None = None,
) -> str:
    body = ["isa = XCBuildConfiguration;"]
    if base_config_ref:
        body.append(f"baseConfigurationReference = {base_config_ref};")
    body.extend(["buildSettings = {", config_settings(settings_map).rstrip(), "};", f"name = {q(name)};"])
    return project.add(key, "\n".join(body))


def add_config_list(project: Project, key: str, debug: str, release: str) -> str:
    return project.add(
        key,
        "\n".join(
            [
                "isa = XCConfigurationList;",
                f"buildConfigurations = ({debug}, {release},);",
                "defaultConfigurationIsVisible = 0;",
                'defaultConfigurationName = "Release";',
            ]
        ),
    )


def add_phase(project: Project, key: str, isa: str, files: list[str], extra: str = "") -> str:
    body = [
        f"isa = {isa};",
        f"buildActionMask = 2147483647;",
        f"files = {plist_array(files)};",
    ]
    if isa == "PBXCopyFilesBuildPhase":
        body.extend(["dstPath = \"\";", extra, "runOnlyForDeploymentPostprocessing = 0;"])
    else:
        body.append("runOnlyForDeploymentPostprocessing = 0;")
    return project.add(key, "\n".join(body))


def add_group(project: Project, key: str, name: str, path: str | None, children: list[str]) -> str:
    body = ["isa = PBXGroup;", f"children = {plist_array(children)};"]
    if name:
        body.append(f"name = {q(name)};")
    if path:
        body.append(f"path = {q(path)};")
    body.append('sourceTree = "<group>";')
    return project.add(key, "\n".join(body))


def add_scheme(root: Path, project: Project, scheme_name: str, target_key: str, target: dict[str, object]) -> None:
    target_id = project.oid(f"target:{target_key}")
    product_id = project.oid(f"product:{target_key}")
    target_name = str(target["name"])
    product_name = str(target["product"])
    runnable = "" if target_key == "widget" else f'''\n      <BuildableProductRunnable runnableDebuggingMode="0">\n         <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" BuildableName="{product_name}" BlueprintName="{target_name}" ReferencedContainer="container:MiKidu.xcodeproj"/>\n      </BuildableProductRunnable>'''
    xml = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
            <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" BuildableName="{product_name}" BlueprintName="{target_name}" ReferencedContainer="container:MiKidu.xcodeproj"/>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">{runnable}
      <CommandLineArguments/>
      <EnvironmentVariables/>
   </LaunchAction>
   <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">{runnable}</ProfileAction>
   <AnalyzeAction buildConfiguration="Debug"/>
   <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
    path = root / "MiKidu.xcodeproj" / "xcshareddata" / "xcschemes" / f"{scheme_name}.xcscheme"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(xml, encoding="utf-8")


def generate(root: Path) -> str:
    project = Project()
    for target in TARGETS.values():
        (root / str(target["source_dir"])).mkdir(parents=True, exist_ok=True)
    (root / "Config").mkdir(parents=True, exist_ok=True)

    config_refs: list[str] = []
    for path in sorted((root / "Config").glob("*"), key=lambda p: p.name):
        if path.is_file() and path.name != "Signing.local.xcconfig":
            config_refs.append(add_file_reference(project, path.relative_to(root).as_posix(), path, False))
    app_groups: dict[str, str] = {}
    source_refs_by_target: dict[str, list[str]] = {}
    resource_buildfiles_by_target: dict[str, list[str]] = {}
    source_buildfiles_by_target: dict[str, list[str]] = {}

    for target_key, target in TARGETS.items():
        directory = root / str(target["source_dir"])
        sources, resources = discover_files(directory)
        children: list[str] = []
        source_buildfiles: list[str] = []
        resource_buildfiles: list[str] = []
        source_refs: list[str] = []
        for path in sources + resources:
            rel = path.relative_to(root).as_posix()
            file_ref = add_file_reference(project, rel, path, True)
            children.append(file_ref)
            if path.suffix == ".swift":
                source_refs.append(file_ref)
                source_buildfiles.append(add_build_file(project, f"source:{rel}", file_ref))
            else:
                resource_buildfiles.append(add_build_file(project, f"resource:{rel}", file_ref))
        app_groups[target_key] = add_group(project, f"group:apps:{target_key}", "", str(target["source_dir"]).split("/")[-1], children)
        source_refs_by_target[target_key] = source_refs
        source_buildfiles_by_target[target_key] = source_buildfiles
        resource_buildfiles_by_target[target_key] = resource_buildfiles

    shared_dir = root / SHARED_DIR
    shared_sources, shared_resources = discover_files(shared_dir)
    shared_children: list[str] = []
    shared_file_refs: dict[str, str] = {}
    for path in shared_sources + shared_resources:
        rel = path.relative_to(root).as_posix()
        file_ref = add_file_reference(project, rel, path, True)
        shared_children.append(file_ref)
        shared_file_refs[rel] = file_ref
    shared_group = add_group(project, "group:apps:shared", "Shared", "Shared", shared_children)
    for target_key in TARGETS:
        selected_sources = shared_sources
        selected_resources = shared_resources
        if target_key == "widget":
            selected_sources = [p for p in shared_sources if p.name in WIDGET_SHARED_SOURCES]
            selected_resources = []
        for path in selected_sources:
            rel = path.relative_to(root).as_posix()
            source_refs_by_target[target_key].append(shared_file_refs[rel])
            source_buildfiles_by_target[target_key].append(
                add_build_file(project, f"source:{target_key}:{rel}", shared_file_refs[rel])
            )
        for path in selected_resources:
            rel = path.relative_to(root).as_posix()
            resource_buildfiles_by_target[target_key].append(
                add_build_file(project, f"resource:{target_key}:{rel}", shared_file_refs[rel])
            )

    apps_group = add_group(project, "group:apps", "Apps", "Apps", [shared_group, *[app_groups[key] for key in TARGETS]])
    config_group = add_group(project, "group:config", "Config", "Config", config_refs)
    tools_dir = root / "tools"
    tool_refs: list[str] = []
    generator_file = tools_dir / "generate_project.py"
    if generator_file.exists():
        tool_refs.append(add_file_reference(project, "tools/generate_project.py", generator_file, False))
    tools_group = add_group(project, "group:tools", "tools", "tools", tool_refs)

    local_package_ref = project.add(
        "package:local",
        "\n".join(["isa = XCLocalSwiftPackageReference;", 'relativePath = ".";']),
    )
    package_dependency_refs: dict[tuple[str, str], str] = {}
    package_build_files: dict[str, list[str]] = {key: [] for key in TARGETS}
    for target_key, target in TARGETS.items():
        for product in target["products"]:  # type: ignore[index]
            dep_id = project.add(
                f"package-product:{target_key}:{product}",
                "\n".join(
                    [
                        "isa = XCSwiftPackageProductDependency;",
                        f"package = {local_package_ref};",
                        f"productName = {q(str(product))};",
                    ]
                ),
            )
            package_dependency_refs[(target_key, str(product))] = dep_id
            package_build_files[target_key].append(
                add_package_build_file(project, f"package-build:{target_key}:{product}", dep_id)
            )

    product_group_children: list[str] = []
    product_refs: dict[str, str] = {}
    for target_key, target in TARGETS.items():
        product_refs[target_key] = project.add(
            f"product:{target_key}",
            "\n".join(
                [
                    "isa = PBXFileReference;",
                    f"explicitFileType = {q(str(target['file_type']))};",
                    f"includeInIndex = 0;",
                    f"path = {q(str(target['product']))};",
                    'sourceTree = "BUILT_PRODUCTS_DIR";',
                ]
            ),
        )
        product_group_children.append(product_refs[target_key])
    products_group = add_group(project, "group:products", "Products", None, product_group_children)

    project_config_list: dict[str, str] = {}
    base_config_id = project.oid("file:Config/Project.xcconfig")
    for configuration in ("Debug", "Release"):
        settings = {
            "ALWAYS_SEARCH_USER_PATHS": "NO",
            "CLANG_ENABLE_MODULES": "YES",
            "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
            "SWIFT_VERSION": "6.0",
        }
        project_config_list[configuration] = add_build_configuration(
            project, f"project-config:{configuration}", configuration, settings, base_config_id
        )
    project_config_list_ref = add_config_list(
        project, "project-config-list", project_config_list["Debug"], project_config_list["Release"]
    )

    target_config_lists: dict[str, str] = {}
    target_ids: dict[str, str] = {}
    target_phase_ids: dict[str, list[str]] = {}
    for target_key, target in TARGETS.items():
        frameworks = package_build_files[target_key]
        sources = source_buildfiles_by_target[target_key]
        resources = resource_buildfiles_by_target[target_key]
        target_phases = [
            add_phase(project, f"phase:{target_key}:sources", "PBXSourcesBuildPhase", sources),
            add_phase(project, f"phase:{target_key}:frameworks", "PBXFrameworksBuildPhase", frameworks),
            add_phase(project, f"phase:{target_key}:resources", "PBXResourcesBuildPhase", resources),
        ]
        if target_key == "ios":
            widget_embed_build = add_build_file(
                project, "embed:widget", product_refs["widget"], ["CodeSignOnCopy", "RemoveHeadersOnCopy"]
            )
            watch_embed_build = add_build_file(
                project, "embed:watch", product_refs["watch"], ["CodeSignOnCopy", "RemoveHeadersOnCopy"]
            )
            target_phases.extend(
                [
                    add_phase(
                        project,
                        "phase:ios:embed-extensions",
                        "PBXCopyFilesBuildPhase",
                        [widget_embed_build],
                        'dstSubfolderSpec = 13;\nname = "Embed App Extensions";',
                    ),
                    add_phase(
                        project,
                        "phase:ios:embed-watch",
                        "PBXCopyFilesBuildPhase",
                        [watch_embed_build],
                        'dstSubfolderSpec = 16;\nname = "Embed Watch Content";',
                    ),
                ]
            )
        target_phase_ids[target_key] = target_phases
        configs: dict[str, str] = {}
        for configuration in ("Debug", "Release"):
            configs[configuration] = add_build_configuration(
                project,
                f"target-config:{target_key}:{configuration}",
                configuration,
                target_settings(target, configuration),
                base_config_id,
            )
        target_config_lists[target_key] = add_config_list(
            project,
            f"target-config-list:{target_key}",
            configs["Debug"],
            configs["Release"],
        )

        dependency_ids: list[str] = []
        if target_key == "ios":
            for dep_target in ("widget", "watch"):
                proxy_id = project.add(
                    f"container-proxy:ios:{dep_target}",
                    "\n".join(
                        [
                            "isa = PBXContainerItemProxy;",
                            f"containerPortal = {project.oid('project')};",
                            "proxyType = 1;",
                            f"remoteGlobalIDString = {project.oid(f'target:{dep_target}')};",
                            f"remoteInfo = {q(str(TARGETS[dep_target]['name']))};",
                        ]
                    ),
                )
                dependency_ids.append(
                    project.add(
                        f"target-dependency:ios:{dep_target}",
                        "\n".join(
                            [
                                "isa = PBXTargetDependency;",
                                f"target = {project.oid(f'target:{dep_target}')};",
                                f"targetProxy = {proxy_id};",
                            ]
                        ),
                    )
                )

        target_ids[target_key] = project.add(
            f"target:{target_key}",
            "\n".join(
                [
                    "isa = PBXNativeTarget;",
                    f"buildConfigurationList = {target_config_lists[target_key]};",
                    f"buildPhases = {plist_array(target_phase_ids[target_key])};",
                    "buildRules = ();",
                    f"dependencies = {plist_array(dependency_ids)};",
                    f"name = {q(str(target['name']))};",
                    f"packageProductDependencies = {plist_array([package_dependency_refs[(target_key, str(p))] for p in target['products']] )};",
                    f"productName = {q(str(target['name']))};",
                    f"productReference = {product_refs[target_key]};",
                    f"productType = {q(str(target['product_type']))};",
                ]
            ),
        )

    root_group = add_group(project, "group:main", "", None, [apps_group, config_group, tools_group, products_group])
    project_id = project.add(
        "project",
        "\n".join(
            [
                "isa = PBXProject;",
                "attributes = {",
                "\t\t\t\tBuildIndependentTargetsInParallel = YES;",
                "\t\t\t\tLastSwiftUpdateCheck = 2700;",
                "\t\t\t\tLastUpgradeCheck = 2700;",
                "\t\t\t\tTargetAttributes = {",
                *[
                    f"\t\t\t\t\t\t{target_ids[key]} = {{ CreatedOnToolsVersion = 27.2; }};"
                    for key in TARGETS
                ],
                "\t\t\t\t};",
                "\t\t\t};",
                f"buildConfigurationList = {project_config_list_ref};",
                'compatibilityVersion = "Xcode 16.0";',
                'developmentRegion = "es";',
                "hasScannedForEncodings = 0;",
                'knownRegions = ("es", Base,);',
                f"mainGroup = {root_group};",
                "packageReferences = (",
                f"\t\t\t\t{local_package_ref},",
                "\t\t\t);",
                f"productRefGroup = {products_group};",
                'projectDirPath = "";',
                'projectRoot = "";',
                f"targets = {plist_array([target_ids[key] for key in TARGETS])};",
            ]
        ),
    )

    # Keep Project object as rootObject and ensure its ID is stable.
    if project_id != project.oid("project"):
        raise RuntimeError("Unexpected project root ID")

    ordered_objects = "\n".join(
        f"\t\t{object_id} = {{\n\t\t\t{body.replace(chr(10), chr(10) + chr(9) + chr(9) + chr(9))}\n\t\t}};"
        for object_id, body in sorted(project.objects.items())
    )
    text = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{}};
\tobjectVersion = 77;
\tobjects = {{
{ordered_objects}
\t}};
\trootObject = {project_id};
}}
"""
    return text


def write_file(path: Path, text: str, check: bool) -> bool:
    if check:
        return path.exists() and path.read_text(encoding="utf-8") == text
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify generated files without writing")
    args = parser.parse_args()

    pbxproj = generate(ROOT)
    project_path = ROOT / "MiKidu.xcodeproj" / "project.pbxproj"
    ok = write_file(project_path, pbxproj, args.check)
    if args.check and not ok:
        print(f"Generated project differs or is missing: {project_path}", file=sys.stderr)
        return 1

    scheme_specs = [
        ("MiKidu-Mac", "mac"),
        ("MiKidu-iPhone", "ios"),
        ("MiKidu-Watch", "watch"),
    ]
    for scheme_name, target_key in scheme_specs:
        # Build schemes from the same stable object IDs as the generated project.
        scheme_path = ROOT / "MiKidu.xcodeproj" / "xcshareddata" / "xcschemes" / f"{scheme_name}.xcscheme"
        if args.check:
            # Scheme generation is deterministic and can be checked by reusing
            # the project's stable ID derivation without writing any files.
            project_model = Project()
            target_id = project_model.oid(f"target:{target_key}")
            product_id = project_model.oid(f"product:{target_key}")
            target = TARGETS[target_key]
            target_name = str(target["name"])
            product_name = str(target["product"])
            runnable = f'''\n      <BuildableProductRunnable runnableDebuggingMode="0">\n         <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" BuildableName="{product_name}" BlueprintName="{target_name}" ReferencedContainer="container:MiKidu.xcodeproj"/>\n      </BuildableProductRunnable>'''
            xml = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
            <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" BuildableName="{product_name}" BlueprintName="{target_name}" ReferencedContainer="container:MiKidu.xcodeproj"/>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">{runnable}
      <CommandLineArguments/>
      <EnvironmentVariables/>
   </LaunchAction>
   <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">{runnable}</ProfileAction>
   <AnalyzeAction buildConfiguration="Debug"/>
   <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
            if not write_file(scheme_path, xml, True):
                print(f"Generated scheme differs or is missing: {scheme_path}", file=sys.stderr)
                ok = False
        else:
            # A lightweight facade makes the same scheme XML as the generator.
            add_scheme(ROOT, _scheme_project_model(TARGETS, target_key), scheme_name, target_key, TARGETS[target_key])
    if args.check and not ok:
        return 1
    if not args.check:
        print(f"Generated {project_path.relative_to(ROOT)} and shared schemes")
        if not (ROOT / "Package.swift").exists():
            print("Package.swift is not present yet; local package links are prepared for the integrator's root package.")
    return 0


def _scheme_project_model(targets: dict[str, dict[str, object]], requested: str) -> Project:
    """Prepare stable target/product IDs needed by add_scheme."""
    project = Project()
    for key in targets:
        project.oid(f"target:{key}")
        project.oid(f"product:{key}")
    return project


if __name__ == "__main__":
    raise SystemExit(main())
