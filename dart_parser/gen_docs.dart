// gen_doc.dart
import 'dart:io';
import 'dart:convert'; // Import for JSON encoding
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:path/path.dart' as p;
import 'package:args/args.dart';

// --- Helper Functions ---

/// Helper function to find Flutter SDK path from package_config.json
Future<String?> _findSdkPathFromProject(String projectPath) async {
  final packageConfigPath =
      p.join(projectPath, '.dart_tool', 'package_config.json');
  stderr.writeln('Info: Attempting to find SDK path from $packageConfigPath');

  try {
    final file = File(packageConfigPath);
    if (!await file.exists()) {
      stderr.writeln(
          'Warning: package_config.json not found at $packageConfigPath');
      return null;
    }

    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;

    // Find the flutter package entry
    final packages = json['packages'] as List?;
    if (packages == null) {
      stderr.writeln(
          'Warning: Invalid package_config.json format: missing "packages" list.');
      return null;
    }

    final flutterPackage = packages.cast<Map<String, dynamic>>().firstWhere(
          (pkg) => pkg['name'] == 'flutter',
          orElse: () => <String, dynamic>{}, // Return empty map if not found
        );

    if (flutterPackage.isEmpty) {
      stderr.writeln(
          'Warning: Could not find "flutter" package entry in package_config.json');
      return null;
    }

    final rootUriString = flutterPackage['rootUri'] as String?;
    if (rootUriString == null) {
      stderr.writeln(
          'Warning: Missing "rootUri" for flutter package in package_config.json');
      return null;
    }

    // The rootUri is usually relative to the package_config.json file itself,
    // represented as a file URI (e.g., '../path/to/sdk/packages/flutter/lib/').
    // We need to resolve it.
    Uri rootUri;
    try {
      // Resolve the rootUri relative to the directory containing package_config.json
      rootUri = p.toUri(p.dirname(packageConfigPath)).resolve(rootUriString);
    } catch (e) {
      stderr.writeln(
          'Warning: Could not parse or resolve flutter rootUri "$rootUriString": $e');
      return null;
    }

    if (!rootUri.isScheme('file')) {
      stderr.writeln(
          'Warning: Flutter package rootUri is not a file URI: $rootUri');
      return null;
    }

    // The URI points to the /lib directory. Iteratively check parent directories.
    final libPath = p.fromUri(rootUri);
    String currentPath = libPath;
    String? foundSdkPath;

    for (int i = 0; i < 5; i++) {
      // Check up to 5 levels up from lib
      currentPath = p.dirname(currentPath);
      if (currentPath == '/' || currentPath == '.' || currentPath.isEmpty) {
        stderr.writeln(
            'Warning: Reached filesystem root or invalid path while searching for SDK root from $libPath.');
        break; // Stop searching if we hit the root or an invalid path
      }

      stderr.writeln('Info: Checking potential SDK root: $currentPath');
      final binDir = Directory(p.join(currentPath, 'bin'));
      final packagesDir = Directory(p.join(currentPath, 'packages'));

      // Check if both bin and packages directories exist
      if (await binDir.exists() && await packagesDir.exists()) {
        // Check specifically for the flutter package subdir as extra validation
        final flutterPackageDir =
            Directory(p.join(currentPath, 'packages', 'flutter'));
        if (await flutterPackageDir.exists()) {
          stderr.writeln('Info: Found valid SDK structure at: $currentPath');
          foundSdkPath = currentPath;
          break; // Found it
        }
      }
    }

    if (foundSdkPath != null) {
      return foundSdkPath;
    } else {
      stderr.writeln(
          'Warning: Could not find a valid SDK structure by searching upwards from $libPath.');
      return null;
    }
  } catch (e, s) {
    stderr.writeln('Error reading or parsing package_config.json: $e\n$s');
    return null;
  }
}

/// Helper function to extract and clean doc comments
/// Reads referenced DartPad example files.
String? _extractDocumentation(Comment? comment, String flutterSdkPath) {
  if (comment == null || !comment.isDocumentation) {
    return null;
  }
  String rawDoc = comment.tokens
      .map((token) => token.lexeme.trim())
      .where((line) => line.startsWith('///'))
      .map((line) => line.replaceFirst(RegExp(r'///\s?'), ''))
      .join('\n')
      .trim(); // Trim leading/trailing whitespace from the whole block

  // Find and replace {@tool dartpad ... ** See code in path ** ... {@end-tool}
  final dartpadRefPattern = RegExp(
    r'\{@tool\s+dartpad.*?\*\*\s*See\s+code\s+in\s+(.*?)\s*\*\*.*?\{@end-tool\}',
    dotAll: true, // Allow . to match newline
    caseSensitive: false,
  );

  String processedDoc = rawDoc.replaceAllMapped(dartpadRefPattern, (match) {
    final path = match.group(1)?.trim();
    if (path != null && path.isNotEmpty) {
      final absolutePath =
          p.normalize(p.join(flutterSdkPath, path)); // Use SDK path
      try {
        // Use sync read for simplicity within visitor flow
        final content = File(absolutePath).readAsStringSync();
        // Return content formatted as code block
        return '\n```dart\n${content.trim()}\n```\n';
      } catch (e) {
        stderr.writeln(
          'Warning: Could not read DartPad example file $absolutePath (referenced in doc comment): $e',
        );
        return '[DartPad Example: $path (Error reading file)]'; // Placeholder on error
      }
    } else {
      // Should not happen if regex matched, but return original block as fallback
      return match.group(0) ?? '';
    }
  });

  return processedDoc.isEmpty ? null : processedDoc;
}

String _buildSignatureFromParameters(
    ConstructorDeclaration node, String constructorName) {
  final buffer = StringBuffer();
  if (node.constKeyword != null) {
    buffer.write('const ');
  }
  buffer.write(constructorName);
  buffer.write('(');

  final params = node.parameters.parameters;
  bool firstParam = true;
  bool inNamed = false;
  bool inPositional = false;

  for (final param in params) {
    // Check parameter type (named, positional optional, required positional)
    final isNamed = param.isNamed;
    final isOptionalPositional = param.isOptionalPositional;
    // isRequiredNamed check needs the element or specific keyword check
    final declaredElement = param.declaredElement; // ParameterElement
    final isRequired = declaredElement?.isRequiredNamed ??
        param
            .isRequiredPositional; // Approximation, covers required named/positional

    // Separator logic
    if (!firstParam) {
      buffer.write(', ');
    } else {
      // Add opening brace/bracket before the first named/optional param
      if (isNamed) {
        buffer.write('{');
        inNamed = true;
      } else if (isOptionalPositional) {
        buffer.write('[');
        inPositional = true;
      }
      firstParam = false; // Now handled
    }

    // Handle opening brace/bracket for subsequent named/optional parameters if needed
    // (This scenario shouldn't happen if parameters are ordered correctly,
    // but included for robustness in case of mixed optional types if allowed)
    if (isNamed && !inNamed) {
      buffer.write('{');
      inNamed = true;
    } else if (isOptionalPositional && !inPositional) {
      buffer.write('[');
      inPositional = true;
    }

    // Required keyword for named parameters
    if (isRequired && isNamed) {
      // isRequired check here
      buffer.write('required ');
    }

    // Get Type string using the resolved element's type
    String typeString = 'dynamic /* unknown type */'; // Default
    if (declaredElement != null) {
      // Need ResolvedUnitResult for types, ensure we have it where this is called
      try {
        // Use getDisplayString for accurate type representation including nullability
        typeString =
            declaredElement.type.getDisplayString(withNullability: true);
      } catch (e) {
        stderr.writeln(
            "Warning: Could not get display string for type of parameter ${declaredElement.name}: $e. Falling back.");
        // Simplified: If getDisplayString fails, we stick with the error default.
      }
    } else {
      stderr.writeln(
          "Warning: Could not get declared element for parameter ${param.name?.lexeme}. Type may be inaccurate.");
      // Attempt fallback using AST type node as above if needed
    }

    buffer.write(typeString);
    buffer.write(' ');

    // Get Name
    final name = param.name?.lexeme;
    if (name != null) {
      buffer.write(name);
    } else {
      // Handle edge cases like super parameters if necessary, but name is usually present
      buffer.write('/* unknown name */');
      stderr.writeln(
          "Warning: Could not get name for parameter AST node: ${param.runtimeType}");
    }

    // Note: Handling default values ` = value` would go here if needed.
    // Note: Handling annotations like @Deprecated would go here.
  }

  // Add closing brace/bracket
  if (inNamed) {
    buffer.write('}');
  }
  if (inPositional) {
    buffer.write(']');
  }

  buffer.write(')');
  return buffer.toString();
}

/// Builds a structured JSON representation of a constructor.
Map<String, dynamic> _buildConstructorJson(
    ConstructorDeclaration node, String constructorName) {
  final Map<String, dynamic> constructorJson = {
    'name': constructorName,
    'is_const': node.constKeyword != null,
    'positional_args': <Map<String, dynamic>>[],
    'named_args': <Map<String, dynamic>>[],
  };

  final params = node.parameters.parameters;

  for (final param in params) {
    final paramData = <String, dynamic>{};

    // Get Name
    final name = param.name?.lexeme;
    if (name != null) {
      paramData['name'] = name;
    } else {
      paramData['name'] = '/* unknown name */';
      stderr.writeln(
          "Warning: Could not get name for parameter AST node: ${param.runtimeType} in $constructorName");
    }

    // Get Type
    String typeString = 'dynamic /* unknown type */';
    final declaredElement = param.declaredElement;
    if (declaredElement != null) {
      try {
        typeString =
            declaredElement.type.getDisplayString(withNullability: true);
      } catch (e) {
        stderr.writeln(
            "Warning: Could not get display string for type of parameter ${paramData['name']} in $constructorName: $e. Falling back.");
      }
    } else {
      stderr.writeln(
          "Warning: Could not get declared element for parameter ${paramData['name']} in $constructorName. Type may be inaccurate.");
    }
    paramData['type'] = typeString;

    // Determine required status
    final isNamed = param.isNamed;
    final isOptionalPositional = param.isOptionalPositional;
    // Combine checks for required status across named and positional parameters
    final isRequired = (declaredElement?.isRequiredNamed ?? false) ||
        (declaredElement?.isRequiredPositional ?? false) ||
        // Handling `required` keyword for positional parameters that might not have an element marked as requiredPositional
        (param is FormalParameter && param.requiredKeyword != null && !isNamed);

    paramData['required'] = isRequired;

    // Add to the correct list based on whether it's named or positional
    if (isNamed) {
      constructorJson['named_args'].add(paramData);
    } else {
      constructorJson['positional_args'].add(paramData);
    }
  }

  return constructorJson;
}

// --- Visitor for Indexing All Docs in a File ---
class _FileIndexerVisitor extends GeneralizingAstVisitor<void> {
  final Map<String, Map<String, dynamic>> docsData; // Reference to the main map
  final String flutterSdkPath; // Added SDK path

  _FileIndexerVisitor(
      this.docsData, this.flutterSdkPath); // Updated constructor

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _indexDeclaration(
      node,
      node.name.lexeme,
      node.documentationComment,
      node.members,
      flutterSdkPath, // Pass SDK path through here too
    );
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    _indexDeclaration(
      node,
      node.name.lexeme,
      node.documentationComment,
      node.members,
      flutterSdkPath, // Pass SDK path through here too
    );
  }

  @override
  void visitGenericTypeAlias(GenericTypeAlias node) {
    _indexDeclaration(
      node,
      node.name.lexeme,
      node.documentationComment,
      const <ClassMember>[],
      flutterSdkPath, // Pass SDK path through here too
    );
  }

  void _indexDeclaration(
    Declaration node,
    String name,
    Comment? docComment,
    Iterable<ClassMember> members,
    String flutterSdkPath, // Pass SDK path through here too
  ) {
    if (!name.startsWith('_')) {
      if (!docsData.containsKey(name)) {
        stderr.writeln('Info: Indexing $name...');
        final String? classDoc =
            _extractDocumentation(docComment, flutterSdkPath);
        final List<Map<String, String?>> constructorsList = [];
        final List<Map<String, dynamic>> constructorsJsonList =
            []; // New list for JSON

        for (final member in members.whereType<ConstructorDeclaration>()) {
          String constructorFullName = name;
          if (member.name != null) {
            constructorFullName = '$name.${member.name!.lexeme}';
          }

          // Build signature string (existing)
          final String signature =
              _buildSignatureFromParameters(member, constructorFullName);

          final String? constructorDoc = _extractDocumentation(
            member.documentationComment,
            flutterSdkPath, // Pass SDK path
          );
          constructorsList.add({
            'name': constructorFullName,
            'signature': signature,
            'documentation': constructorDoc,
          });

          // Build constructor JSON (new)
          final Map<String, dynamic> constructorJson =
              _buildConstructorJson(member, constructorFullName);
          constructorsJsonList.add(constructorJson);
        }

        docsData[name] = {
          'classDoc': classDoc,
          'constructors': constructorsList, // Keep existing key
          'constructors_json': constructorsJsonList, // Add new key
        };
      } else {
        stderr.writeln('Info: Skipping duplicate definition found for $name.');
      }
    }
  }
}
// --- End of Visitors ---

// --- Main Entry Point ---
Future<void> main(List<String> arguments) async {
  // --- Argument Parser Setup ---
  final parser = ArgParser()
    ..addOption(
      'sdk-path',
      abbr: 's',
      help:
          'Path to the Flutter SDK root (optional, attempts auto-detect from project-path).',
      mandatory: false,
    )
    ..addOption(
      'project-path',
      abbr: 'p',
      help:
          'Path to a Flutter project directory with dependencies resolved (contains pubspec.yaml and .dart_tool/package_config.json). Provides context for resolving types and finding the SDK.',
      mandatory: true,
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show usage information.',
    );

  ArgResults argResults;
  try {
    argResults = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('Error parsing arguments: ${e.message}\n\n${parser.usage}');
    exit(2);
  }

  // --- Handle Help Flag ---
  if (argResults['help']) {
    print('Flutter Documentation Indexer');
    print(
        '\nUsage: dart run gen_docs.dart --project-path <path/to/project> [--sdk-path <path/to/sdk>]');
    print(
        '\nOutputs a JSON index of all public widget/class/mixin/typedef docs found in the Flutter SDK determined by the project path (or the manually specified SDK path) to stdout.');
    print('\n${parser.usage}');
    print('\nExamples:');
    print('  dart run gen_docs.dart --project-path ./my_flutter_app');
    print(
        '  dart run gen_docs.dart --project-path ./my_flutter_app --sdk-path /path/to/flutter_sdk');
    exit(0);
  }

  // --- Ensure only one mode is selected ---
  if (argResults.rest.isNotEmpty) {
    stderr.writeln(
        'Error: Unexpected positional arguments found: ${argResults.rest}');
    stderr.writeln(
        'This script only accepts options like --project-path and --sdk-path.');
    stderr.writeln('\n${parser.usage}');
    exit(2);
  }

  // --- Determine and Validate SDK Path ---
  String? flutterSdkPath = argResults['sdk-path'];
  String? determinedSdkPathSource = '--sdk-path argument'; // Track source
  final String projectPath =
      argResults['project-path']!; // Mandatory, so ! is safe
  String? dartSdkPath; // Declare dartSdkPath here

  if (flutterSdkPath == null) {
    // SDK path not manually provided, try to find it from the mandatory project path
    determinedSdkPathSource = 'project package_config.json';
    flutterSdkPath = await _findSdkPathFromProject(projectPath);
  }

  // Validate the determined path
  if (flutterSdkPath == null) {
    stderr.writeln(
      'Error: Flutter SDK path could not be determined ($determinedSdkPathSource failed).',
    );
    stderr.writeln(
      'Please provide a valid --project-path where `flutter pub get` has run, or specify the SDK manually using --sdk-path.',
    );
    exit(1);
  } else {
    final flutterPackageLibPath =
        p.join(flutterSdkPath, 'packages', 'flutter', 'lib');
    if (!Directory(flutterPackageLibPath).existsSync()) {
      stderr.writeln(
          'Error: Invalid Flutter SDK path determined ($determinedSdkPathSource): $flutterSdkPath');
      stderr.writeln('       Directory not found: $flutterPackageLibPath');
      exit(1);
    }
    stderr.writeln(
        'Info: Using Flutter SDK path ($determinedSdkPathSource): $flutterSdkPath');

    // --- Derive and Validate internal Dart SDK Path ---
    dartSdkPath =
        p.join(flutterSdkPath, 'bin', 'cache', 'dart-sdk'); // Assign here
    final dartSdkCoreLibPath =
        p.join(dartSdkPath!, 'lib', 'core', 'core.dart'); // Use ! for safety
    stderr.writeln('Info: Checking for internal Dart SDK at: $dartSdkPath');
    if (!await File(dartSdkCoreLibPath).exists()) {
      stderr.writeln(
          'Error: Could not find internal Dart SDK within the Flutter SDK.');
      stderr.writeln('       Expected core library at: $dartSdkCoreLibPath');
      stderr.writeln(
          '       Make sure the Flutter SDK is correctly installed and `flutter doctor` runs successfully.');
      exit(1);
    }
    stderr.writeln('Info: Found internal Dart SDK.');
  }
  // flutterSdkPath is guaranteed non-null and validated now
  // dartSdkPath is also guaranteed non-null and validated now
  if (dartSdkPath == null) {
    // This should theoretically not happen if flutterSdkPath validation passed
    stderr.writeln('Error: Internal Dart SDK path was not derived correctly.');
    exit(1);
  }

  // Directly run the indexing function
  stderr.writeln('--- Running Documentation Indexing ---');
  // Pass both Flutter root path and internal Dart SDK path
  await runIndexAll(
      flutterSdkPath!, projectPath, dartSdkPath!); // Use ! assertion
}

// --- Function for Indexing All Documentation ---
Future<void> runIndexAll(
    String flutterSdkPath, String projectPath, String dartSdkPath) async {
  // Added dartSdkPath
  stderr.writeln('--- Running in Index All Mode ---');
  final Map<String, Map<String, dynamic>> allDocsData = {}; // Main result map

  // Find files to analyze (same logic as list mode)
  final List<String> targetDirs = [
    p.join(flutterSdkPath, 'packages', 'flutter', 'lib', 'src', 'widgets'),
    p.join(flutterSdkPath, 'packages', 'flutter', 'lib', 'src', 'material'),
    p.join(flutterSdkPath, 'packages', 'flutter', 'lib', 'src', 'cupertino'),
    p.join(flutterSdkPath, 'packages', 'flutter', 'lib'),
  ];
  final List<String> filesToAnalyze = [];
  stderr.writeln('Info: Scanning for .dart files...');
  for (final dirPath in targetDirs) {
    /* ... file scanning logic ... */
    final directory = Directory(dirPath);
    if (!await directory.exists()) {
      stderr.writeln('Warning: Directory does not exist, skipping: $dirPath');
      continue;
    }
    try {
      bool recursive = dirPath.contains(p.join('lib', 'src'));
      await for (final entity in directory.list(
        recursive: recursive,
        followLinks: false,
      )) {
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            !entity.path.contains(p.separator + 'test' + p.separator)) {
          filesToAnalyze.add(entity.path);
        }
      }
    } catch (e) {
      stderr.writeln('Error listing files in $dirPath: $e');
    }
  }
  stderr.writeln(
    'Info: Found ${filesToAnalyze.length} .dart files to analyze for indexing.',
  );
  if (filesToAnalyze.isEmpty) {
    stderr.writeln('Error: No .dart files found.');
    exit(1);
  }

  // Setup analysis context based on whether projectPath is provided
  AnalysisContextCollection collection;
  AnalysisSession session;
  stderr.writeln(
      'Info: Creating analysis context rooted in project: $projectPath');
  collection = AnalysisContextCollection(
    includedPaths: [projectPath], // Root context in the project
    sdkPath: dartSdkPath, // Use the derived internal Dart SDK path here
  );
  // Use the session from the project context to analyze SDK files
  session = collection.contextFor(projectPath).currentSession;

  stderr.writeln('Info: Analyzing files and extracting documentation...');
  final stopwatch = Stopwatch()..start();
  int count = 0;
  final total = filesToAnalyze.length;

  // Analyze each file and populate the allDocsData map
  for (final filePath in filesToAnalyze) {
    count++;
    if (count % 20 == 0 || count == total) {
      // More frequent progress for longer task
      stderr.writeln(
        'Info: Indexed $count / $total files... (${stopwatch.elapsed.inSeconds}s)',
      );
    }
    try {
      // Use the session determined above (either project-based or file-based)
      // If projectPath wasn't provided, we might need to get context per file
      // but try using the potentially limited session first.
      final AnalysisSession currentSession = session;

      // Need ResolvedUnitResult to ensure comments are properly associated
      // Use the determined session to resolve the SDK file
      final result = await currentSession.getResolvedUnit(filePath);

      if (result is ResolvedUnitResult) {
        // Report significant errors for this file
        final errors = result.errors
            .where((e) => e.errorCode.errorSeverity == ErrorSeverity.ERROR)
            .toList();
        if (errors.isNotEmpty) {
          stderr.writeln(
            'Warning: Analysis errors found in $filePath (may affect doc accuracy):',
          );
          errors.take(3).forEach(
                (e) => stderr.writeln('  - ${e.message}'),
              ); // Log first few
        }
        // Use the indexer visitor, passing the main map and SDK path
        final visitor = _FileIndexerVisitor(allDocsData, flutterSdkPath);
        result.unit.accept(visitor);
      } else {
        stderr.writeln(
          'Warning: Could not resolve unit for $filePath. Skipping.',
        );
      }
    } catch (e, s) {
      stderr.writeln('Error: Failed processing file $filePath: $e\n$s');
      // Continue processing other files
    }
  }
  stopwatch.stop();
  stderr.writeln(
    'Info: Indexing analysis complete in ${stopwatch.elapsed.inSeconds} seconds.',
  );

  // Convert the final map to JSON
  stderr.writeln('Info: Encoding documentation map to JSON...');
  String jsonOutput;
  try {
    // Use an encoder with indentation for slightly more readable output (optional)
    final encoder = JsonEncoder.withIndent('  ');
    jsonOutput = encoder.convert(allDocsData);
    // jsonOutput = jsonEncode(allDocsData); // For compact output
  } catch (e, s) {
    stderr.writeln('\n!!! Error encoding data to JSON !!!');
    stderr.writeln('$e');
    stderr.writeln('$s');
    // Attempt to print problematic keys/values if possible? Difficult.
    stderr.writeln('Attempting basic JSON encoding as fallback...');
    try {
      jsonOutput = jsonEncode(allDocsData); // Fallback to basic encoder
    } catch (e2) {
      stderr.writeln('Fallback JSON encoding also failed: $e2');
      exit(1); // Give up if basic encoding fails
    }
  }

  stderr.writeln('--- Indexing Complete ---');
  stderr.writeln('Indexed documentation for ${allDocsData.length} items.');
  // Print the final JSON string to standard output
  print(jsonOutput);
  exit(0); // Success
}
