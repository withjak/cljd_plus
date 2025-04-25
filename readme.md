# Work in Progress

This repository is designed to offer:

- [X] Documentation (including examples and constructor signatures) when hovering over Flutter widgets in ClojureDart
- [ ] Auto-complete functionality
    - [X] Suggest flutter widget paramaters (triggered with dot "." )
- [ ] Navigation to the source Flutter file
- [ ] A VSCode extension

Currently, the hover and autocomplete features are operational, but requires a few manual setup steps.

## Steps to Enable Documentation and Auto complete
1. Install [Joyride](https://marketplace.visualstudio.com/items/?itemName=betterthantomorrow.joyride) vscode extension
2. Copy the `.joyride` and `dart_parser` directories into the root directory of your ClojureDart project.
3. In the clojuredart projects root directory, run `dart pub get` to generate the `.dart_tool/package_config.json` file.
4. Run below commands:
```bash
cd dart_parser

# this is different from step 3.
dart pub get

# this file is expected by joyride to show docs on hover over panel
dart run gen_docs.dart --project-path PATH_TO_YOUR_PROJECT_ROOT_DIR > /tmp/cljd_flutter_widget_docs.json
```
5. Restart your IDE.
6. Hover over any Flutter widget name in a `.cljd` file. Note: The name should be formatted as `m/Name`, for example, `m/Text`.

### Additional Information

- The `gen_docs` command relies on the `.dart_tool/package_config.json` file to locate the Flutter SDK directory. It searches for the `"flutter"` entry, so ensure that Flutter is listed as a dependency in your pubspec.yaml file.
- The `--project-path PATH_TO_YOUR_PROJECT_ROOT_DIR` argument must be an absolute path.
- The `/tmp/cljd_flutter_widget_docs.json` file is a mapping from widget names to their documentation. Joyride requires this file to display documentation in the hover panel.