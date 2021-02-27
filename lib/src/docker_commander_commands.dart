import 'package:swiss_knife/swiss_knife.dart';

import 'docker_commander_host.dart';

abstract class DockerCMDExecutor {
  /// Returns [true] if runner of [containerName] is running.
  bool isContainerRunnerRunning(String containerName);

  /// Executes a Docker [command] with [args]
  Future<DockerProcess> command(String command, List<String> args);

  /// Executes a [command] inside this container with [args]
  /// Only executes if [isContainerRunnerRunning] [containerName] returns true.
  Future<DockerProcess> exec(
    String containerName,
    String command,
    List<String> args, {
    bool outputAsLines = true,
    int outputLimit,
    OutputReadyFunction stdoutReadyFunction,
    OutputReadyFunction stderrReadyFunction,
    OutputReadyType outputReadyType,
  });

  /// Calls [exec] than [waitExit].
  Future<int> execAndWaitExit(
      String containerName, String command, List<String> args,
      {int desiredExitCode}) async {
    var process = await exec(containerName, command, args);
    return process.waitExit(desiredExitCode: desiredExitCode);
  }

  /// Calls [exec] than [waitExit].
  Future<bool> execAnConfirmExit(String containerName, String command,
      List<String> args, int desiredExitCode) async {
    var exitCode = await execAndWaitExit(containerName, command, args,
        desiredExitCode: desiredExitCode);
    return exitCode != null;
  }

  /// Calls [exec] than [waitStdout].
  Future<Output> execAndWaitStdout(
      String containerName, String command, List<String> args,
      {int desiredExitCode}) async {
    var process = await exec(containerName, command, args);
    return process.waitStdout(desiredExitCode: desiredExitCode);
  }

  /// Calls [exec] than [waitStderr].
  Future<Output> execAndWaitStderr(
      String containerName, String command, List<String> args,
      {int desiredExitCode}) async {
    var process = await exec(containerName, command, args);
    return process.waitStderr(desiredExitCode: desiredExitCode);
  }

  /// Calls [execAndWaitStdoutAsString] and returns [Output.asString].
  Future<String> execAndWaitStdoutAsString(
      String containerName, String command, List<String> args,
      {bool trim = false, int desiredExitCode, Pattern dataMatcher}) async {
    var output = await execAndWaitStdout(containerName, command, args,
        desiredExitCode: desiredExitCode);
    return _waitOutputAsString(output, trim, dataMatcher);
  }

  /// Calls [execAndWaitStderrAsString] and returns [Output.asString].
  Future<String> execAndWaitStderrAsString(
      String containerName, String command, List<String> args,
      {bool trim = false, int desiredExitCode, Pattern dataMatcher}) async {
    var output = await execAndWaitStderr(containerName, command, args,
        desiredExitCode: desiredExitCode);
    return _waitOutputAsString(output, trim, dataMatcher);
  }

  Future<String> _waitOutputAsString(Output output, bool trim,
      [Pattern dataMatcher]) async {
    if (output == null) return null;
    dataMatcher ??= RegExp(r'.');
    await output.waitForDataMatch(dataMatcher);
    var s = output.asString;
    if (trim ?? false) {
      s = s.trim();
    }
    return s;
  }

  final Map<String, Map<String, String>> _whichCache = {};

  /// Call POSIX `which` command.
  /// Calls [exec] with command `which` and args [commandName].
  /// Caches response than returns the executable path for [commandName].
  Future<String> execWhich(String containerName, String commandName,
      {bool ignoreCache, String def}) async {
    ignoreCache ??= false;

    if (isEmptyString(commandName, trim: true)) return null;

    commandName = commandName.trim();

    var containerCache =
        _whichCache.putIfAbsent(containerName, () => <String, String>{});
    String cached;

    if (!ignoreCache) {
      cached = containerCache[commandName];
      if (cached != null) {
        return cached.isNotEmpty ? cached : def;
      }
    }

    var path = await execAndWaitStdoutAsString(
        containerName, 'which', [commandName],
        trim: true, desiredExitCode: 0, dataMatcher: commandName);
    path ??= '';

    containerCache[commandName] = path;

    return path.isNotEmpty ? path : def;
  }
}

abstract class DockerCMD {
  /// Returns the container IP by [name].
  static Future<String> getContainerIP(
      DockerCMDExecutor executor, String name) async {
    var process = await executor.command('container', ['inspect', name]);
    var exitOK = await process.waitExitAndConfirm(0);
    if (!exitOK) return null;

    await process.stdout.waitForDataMatch('IPAddress');
    var json = process.stdout.asString;
    if (isEmptyString(json, trim: true)) return null;

    var inspect = parseJSON(json);

    var list = inspect is List ? inspect : [];
    var networkSettings = list
        .whereType<Map>()
        .where((e) => e.containsKey('NetworkSettings'))
        .map((e) => e['NetworkSettings'])
        .whereType<Map>()
        .firstWhere((e) => e.containsKey('IPAddress'), orElse: () => null);

    var ip = networkSettings != null ? networkSettings['IPAddress'] : null;

    if (isEmptyString(ip, trim: true)) {
      var networks = networkSettings['Networks'] as Map;
      ip = networks.values
          .where((e) => isNotEmptyString(e['IPAddress']))
          .map((e) => e['IPAddress'])
          .first;
    }

    return ip;
  }

  static Future<Map<String, bool>> addContainersHostMapping(
      DockerCMDExecutor executor,
      Map<String, Map<String, String>> containersHostMapping) async {
    var allHostMapping = <String, String>{};
    for (var hostMapping in containersHostMapping.values) {
      allHostMapping.addAll(hostMapping);
    }

    var oks = <String, bool>{};

    for (var containerName in containersHostMapping.keys) {
      var hostMapping = containersHostMapping[containerName];
      var allHostMapping2 = Map<String, String>.from(allHostMapping);

      for (var containerHost in hostMapping.keys) {
        allHostMapping2.remove(containerHost);
      }

      if (allHostMapping2.isEmpty) {
        oks[containerName] = true;
        break;
      }

      var ok = await addContainerHostMapping(
          executor, containerName, allHostMapping2);
      oks[containerName] = ok;
    }

    return oks;
  }

  static Future<bool> addContainerHostMapping(DockerCMDExecutor executor,
      String containerName, Map<String, String> hostMapping) async {
    var hostMap = '\n' +
        hostMapping.entries.map((e) {
          var host = e.key;
          var ip = e.value;
          return '$ip $host';
        }).join('\n') +
        '\n';

    return appendFile(executor, containerName, '/etc/hosts', hostMap,
        sudo: true);
  }

  /// Call POSIX `cat` command.
  /// Calls [exec] with command `cat` and args [filePath].
  /// Returns the executable path for [filePath].
  static Future<String> execCat(
      DockerCMDExecutor executor, String containerName, String filePath,
      {bool trim = false}) async {
    var catBin =
        await executor.execWhich(containerName, 'cat', def: '/bin/cat');
    var content = await executor.execAndWaitStdoutAsString(
        containerName, catBin, [filePath],
        trim: trim, desiredExitCode: 0);
    return content;
  }

  /// Executes a shell [script]. Tries to use `bash` or `sh`.
  /// Note that [script] should be inline, without line breaks (`\n`).
  static Future<DockerProcess> execShell(
      DockerCMDExecutor executor, String containerName, String script,
      {bool sudo = false}) async {
    var bin = await executor.execWhich(containerName, 'bash');

    if (isEmptyString(bin)) {
      bin = await executor.execWhich(containerName, 'sh', def: '/bin/sh');
    }

    script =
        script.replaceAll(RegExp(r'(?:\r\n|\r|\n)', multiLine: false), ' ');

    if (sudo ?? false) {
      var sudoBin =
          await executor.execWhich(containerName, 'sudo', def: '/bin/sudo');
      return executor.exec(containerName, sudoBin, [bin, '-c', script]);
    } else {
      return executor.exec(containerName, bin, ['-c', script]);
    }
  }

  /// Save the file [filePath] with [content], inside [containerName].
  static Future<bool> putFile(DockerCMDExecutor executor, String containerName,
      String filePath, String content,
      {bool sudo = false, bool append = false}) async {
    var base64Bin = await executor.execWhich(containerName, 'base64',
        def: '/usr/bin/base64');

    var base64 = Base64.encode(content);

    var teeParam = append ? '-a' : '';

    var script =
        'echo "$base64" | $base64Bin --decode | tee $teeParam $filePath > /dev/null ';

    var shell = await execShell(executor, containerName, script);

    var ok = await shell.waitExitAndConfirm(0);
    return ok;
  }

  /// Append to the file [filePath] with [content], inside [containerName].
  static Future<bool> appendFile(DockerCMDExecutor executor,
      String containerName, String filePath, String content,
      {bool sudo = false}) async {
    return putFile(executor, containerName, filePath, content,
        sudo: sudo, append: true);
  }

  /// Executes Docker command `docker ps --format "{{.Names}}"`
  static Future<List<String>> psContainerNames(DockerCMDExecutor executor,
      {bool all = true}) async {
    var process = await executor.command('ps', [
      if (all) '-a',
      '--format',
      '{{.Names}}',
    ]);
    var exitCode = await process.waitExit();
    if (exitCode != 0) return null;
    var output = process.stdout.asString;
    var names =
        output.replaceAll(RegExp(r'\s+'), ' ').trim().split(RegExp(r'\s+'));
    return names;
  }

  /// Creates a Docker network with [networkName].
  static Future<String> createNetwork(
      DockerCMDExecutor executor, String networkName) async {
    if (isEmptyString(networkName, trim: true)) return null;
    networkName = networkName.trim();

    var process = await executor.command('network', ['create', networkName]);
    var exitCode = await process.waitExit();
    return exitCode == 0 ? networkName : null;
  }

  /// Removes a Docker network with [networkName].
  static Future<bool> removeNetwork(
      DockerCMDExecutor executor, String networkName) async {
    if (isEmptyString(networkName, trim: true)) return null;
    networkName = networkName.trim();

    var process = await executor.command('network', ['rm', networkName]);
    var exitCode = await process.waitExit();
    return exitCode == 0;
  }
}