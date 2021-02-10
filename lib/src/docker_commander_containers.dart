import 'package:swiss_knife/swiss_knife.dart';

import 'docker_commander_base.dart';
import 'docker_commander_host.dart';

/// Configuration for a Container.
class DockerContainerConfig {
  final String image;
  final String version;
  final List<String> imageArgs;
  final String name;
  final String network;
  final String hostname;
  final List<String> ports;
  final List<int> hostPorts;
  final List<int> containerPorts;
  final Map<String, String> environment;
  final bool cleanContainer;
  final int outputLimit;
  final bool outputAsLines;
  final OutputReadyFunction stdoutReadyFunction;
  final OutputReadyFunction stderrReadyFunction;

  DockerContainerConfig(
    this.image, {
    this.version,
    this.imageArgs,
    this.name,
    this.network,
    this.hostname,
    this.ports,
    this.hostPorts,
    this.containerPorts,
    this.environment,
    this.cleanContainer,
    this.outputLimit,
    this.outputAsLines,
    this.stdoutReadyFunction,
    this.stderrReadyFunction,
  });

  DockerContainerConfig copy({
    String image,
    String version,
    List<String> imageArgs,
    String name,
    String network,
    String hostname,
    List<String> ports,
    List<int> hostPorts,
    List<int> containerPorts,
    Map<String, String> environment,
    bool cleanContainer,
    int outputLimit,
    bool outputAsLines,
    OutputReadyFunction stdoutReadyFunction,
    OutputReadyFunction stderrReadyFunction,
  }) {
    return DockerContainerConfig(
      image ?? this.image,
      version: version ?? this.version,
      imageArgs: imageArgs ?? this.imageArgs,
      name: name ?? this.name,
      network: network ?? this.network,
      hostname: hostname ?? this.hostname,
      ports: ports ?? this.ports,
      hostPorts: hostPorts ?? this.hostPorts,
      containerPorts: containerPorts ?? this.containerPorts,
      environment: environment ?? this.environment,
      cleanContainer: cleanContainer ?? this.cleanContainer,
      outputLimit: outputLimit ?? this.outputLimit,
      outputAsLines: outputAsLines ?? this.outputAsLines,
      stdoutReadyFunction: stdoutReadyFunction ?? this.stdoutReadyFunction,
      stderrReadyFunction: stderrReadyFunction ?? this.stderrReadyFunction,
    );
  }

  Future<DockerContainer> run(DockerCommander dockerCommander,
      {String name,
      String network,
      String hostname,
      List<int> hostPorts,
      bool cleanContainer = true,
      int outputLimit}) {
    var mappedPorts = ports?.toList();

    hostPorts ??= this.hostPorts;

    if (hostPorts != null &&
        containerPorts != null &&
        hostPorts.isNotEmpty &&
        containerPorts.isNotEmpty) {
      mappedPorts ??= <String>[];

      var portsLength = Math.min(hostPorts.length, containerPorts.length);

      for (var i = 0; i < portsLength; ++i) {
        var p1 = hostPorts[i];
        var p2 = containerPorts[i];
        mappedPorts.add('$p1:$p2');
      }

      mappedPorts = mappedPorts.toSet().toList();
    }

    return dockerCommander.run(
      image,
      version: version,
      imageArgs: imageArgs,
      name: name ?? this.name,
      ports: mappedPorts,
      network: network ?? this.network,
      hostname: hostname ?? this.hostname,
      environment: environment,
      cleanContainer: cleanContainer ?? this.cleanContainer,
      outputAsLines: outputAsLines,
      outputLimit: outputLimit ?? this.outputLimit,
      stdoutReadyFunction: stdoutReadyFunction,
      stderrReadyFunction: stderrReadyFunction,
    );
  }
}

class PostgreSQLContainer extends DockerContainerConfig {
  PostgreSQLContainer(
      {String pgUser,
      String pgPassword,
      String pgDatabase,
      List<int> hostPorts})
      : super(
          'postgres',
          version: 'latest',
          hostPorts: hostPorts,
          containerPorts: [5432],
          environment: {
            if (pgUser != null) 'POSTGRES_USER': pgUser,
            'POSTGRES_PASSWORD': pgPassword,
            if (pgDatabase != null) 'POSTGRES_DB': pgDatabase,
          },
          outputAsLines: true,
          stdoutReadyFunction: (output, line) =>
              line.contains('database system is ready to accept connections'),
        );
}
