<#
.SYNOPSIS
  Narrow TCP forwarder from one Windows interface to Edge on localhost.

.DESCRIPTION
  WSL NAT mode cannot reach a Windows service bound only to 127.0.0.1. This
  process binds only the Windows gateway address visible to WSL, never Any,
  and forwards each connection to Edge's Windows-local CDP listener.
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$ListenAddress,
  [int]$ListenPort = 9223,
  [int]$TargetPort = 9222
)

$ErrorActionPreference = 'Stop'
if ($ListenAddress -in @('0.0.0.0', '::', '*')) {
  throw 'Wildcard listen addresses are prohibited for authenticated browser control.'
}

Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Net;
using System.Net.Sockets;
using System.Threading.Tasks;

public static class CdpForwarder {
  public static async Task RunAsync(string listenAddress, int listenPort, int targetPort) {
    var address = IPAddress.Parse(listenAddress);
    if (IPAddress.Any.Equals(address) || IPAddress.IPv6Any.Equals(address)) {
      throw new InvalidOperationException("Wildcard listen addresses are prohibited.");
    }

    var listener = new TcpListener(address, listenPort);
    listener.Start();
    Console.Error.WriteLine(
      "Forwarding " + address + ":" + listenPort + " -> 127.0.0.1:" + targetPort
    );
    while (true) {
      var client = await listener.AcceptTcpClientAsync();
      var ignored = HandleAsync(client, targetPort);
    }
  }

  static async Task HandleAsync(TcpClient client, int targetPort) {
    try {
      using (client)
      using (var upstream = new TcpClient()) {
        await upstream.ConnectAsync(IPAddress.Loopback, targetPort);
        using (var clientStream = client.GetStream())
        using (var upstreamStream = upstream.GetStream()) {
          var clientToUpstream = clientStream.CopyToAsync(upstreamStream);
          var upstreamToClient = upstreamStream.CopyToAsync(clientStream);
          await Task.WhenAny(clientToUpstream, upstreamToClient);
        }
      }
    } catch {
      // A single reset/aborted browser connection must not kill the listener.
    }
  }
}
'@

[CdpForwarder]::RunAsync($ListenAddress, $ListenPort, $TargetPort).GetAwaiter().GetResult()
