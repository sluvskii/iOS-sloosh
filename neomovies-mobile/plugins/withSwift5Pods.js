const { withDangerousMod, withXcodeProject } = require('@expo/config-plugins');
const fs = require('fs');
const path = require('path');

// Step 1: Patch Podfile so all Pods use Swift 5.9
const withSwiftPods = (config) =>
  withDangerousMod(config, [
    'ios',
    (cfg) => {
      const podfile = path.join(cfg.modRequest.platformProjectRoot, 'Podfile');
      let contents = fs.readFileSync(podfile, 'utf8');

      const patch = `
  # Force Swift 5.9 for all pods (required by expo-modules-core)
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['SWIFT_VERSION'] = '5.9'
    end
  end`;

      // Remove any previously injected SWIFT_VERSION block to avoid duplicates
      contents = contents.replace(
        /\n\s*# Force Swift 5\.9[\s\S]*?end\n/g,
        '\n'
      );

      // Strategy 1: insert after react_native_post_install(...) call
      if (/react_native_post_install\s*\(/.test(contents)) {
        contents = contents.replace(
          /(react_native_post_install\s*\([\s\S]*?\)\s*\n)([ \t]*end\s*\n[ \t]*end)/,
          `$1${patch}\n$2`
        );
      } else {
        // Strategy 2: insert before the closing `end` of the post_install block
        contents = contents.replace(
          /(post_install\s+do\s+\|installer\|\s*\n)([\s\S]*?)(^end\s*$)/m,
          `$1$2${patch}\n$3`
        );
      }

      fs.writeFileSync(podfile, contents);
      return cfg;
    },
  ]);

// Step 2: Patch the main Xcode project so the app target also uses Swift 5.9
const withSwiftXcodeProject = (config) =>
  withXcodeProject(config, (cfg) => {
    const project = cfg.modResults;
    const configurations = project.pbxXCBuildConfigurationSection();

    for (const key of Object.keys(configurations)) {
      const buildConfig = configurations[key];
      if (buildConfig && typeof buildConfig === 'object' && buildConfig.buildSettings) {
        buildConfig.buildSettings['SWIFT_VERSION'] = '5.9';
      }
    }

    return cfg;
  });

// Compose both patches
module.exports = (config) => withSwiftXcodeProject(withSwiftPods(config));
