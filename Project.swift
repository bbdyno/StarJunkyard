import ProjectDescription

let project = Project(
    name: "StarJunkyard",
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
            "TARGETED_DEVICE_FAMILY": "1,2",
            "CODE_SIGN_STYLE": "Automatic",
            "DEVELOPMENT_TEAM": ""
        ]
    ),
    targets: [
        .target(
            name: "StarJunkyard",
            destinations: [.iPhone, .iPad],
            product: .app,
            bundleId: "com.bbdyno.starjunkyard",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDevelopmentRegion": "ko",
                "CFBundleDisplayName": "별을 줍는 고물상",
                "CFBundleLocalizations": ["ko", "en"],
                "UIApplicationSceneManifest": [
                    "UIApplicationSupportsMultipleScenes": false,
                    "UISceneConfigurations": [
                        "UIWindowSceneSessionRoleApplication": [[
                            "UISceneConfigurationName": "Default Configuration",
                            "UISceneDelegateClassName": "$(PRODUCT_MODULE_NAME).SceneDelegate"
                        ]]
                    ]
                ],
                "UILaunchScreen": [:],
                "UIRequiresFullScreen": true,
                "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
                "UISupportedInterfaceOrientations~ipad": ["UIInterfaceOrientationPortrait"]
            ]),
            sources: ["StarJunkyard/Sources/**"],
            resources: [
                "StarJunkyard/Resources/**",
                "content/**",
                "golden/**",
                "art-export/production/**"
            ],
            scripts: [
                .pre(
                    script: """
                    if [ "${CONFIGURATION}" = "Release" ]; then
                      cd "${SRCROOT}"
                      /usr/bin/python3 tools/validate_project.py --release
                    fi
                    """,
                    name: "Validate Production Pixel Assets",
                    basedOnDependencyAnalysis: false
                )
            ],
            settings: .settings(
                base: [
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "",
                    "CODE_SIGN_ENTITLEMENTS": "StarJunkyard/StarJunkyard.entitlements",
                    "ENABLE_USER_SCRIPT_SANDBOXING": "NO"
                ]
            )
        ),
        .target(
            name: "StarJunkyardTests",
            destinations: [.iPhone, .iPad],
            product: .unitTests,
            bundleId: "com.bbdyno.starjunkyard.tests",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: ["StarJunkyardTests/**"],
            resources: ["content/**"],
            dependencies: [.target(name: "StarJunkyard")]
        )
    ],
    schemes: [
        .scheme(
            name: "StarJunkyard",
            shared: true,
            buildAction: .buildAction(targets: ["StarJunkyard", "StarJunkyardTests"]),
            testAction: .targets(["StarJunkyardTests"]),
            runAction: .runAction(
                executable: .executable("StarJunkyard"),
                options: .options(storeKitConfigurationPath: "StarJunkyard/StarJunkyard.storekit")
            )
        )
    ],
    additionalFiles: ["StarJunkyard/StarJunkyard.storekit"]
)
