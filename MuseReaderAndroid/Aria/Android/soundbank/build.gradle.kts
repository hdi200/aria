plugins {
    id("com.android.asset-pack")
}

assetPack {
    packName.set("soundbank")
    dynamicDelivery { deliveryType.set("install-time") }
}

// Reuse the shared sound bank without copying it into version control.
val stageSoundbank by tasks.registering(Sync::class) {
    from("../app/ios-assets") { include("ios/*.sf2") }
    into("src/main/assets")
    doLast {
        require(file("src/main/assets/ios/MuseScore_General.sf2").isFile) {
            "Missing shared MuseScore sound bank; check the ios-assets symlink."
        }
    }
}
tasks.matching { it.name.startsWith("generate") && it.name.endsWith("AssetPackManifest")
    || it.name.startsWith("merge") && it.name.endsWith("Assets")
    || it.name.startsWith("package") && it.name.endsWith("Assets")
}.configureEach { dependsOn(stageSoundbank) }
