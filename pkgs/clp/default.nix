{
  lib,
  writeShellApplication,
}:
writeShellApplication {
  name = "clp";
  text = ''
    if (( $# > 1 )); then
      echo "usage: clp [--image|--text]" >&2
      exit 2
    fi

    case "''${1:-}" in
      "") export CLP_FORMAT=auto ;;
      --image) export CLP_FORMAT=image ;;
      --text) export CLP_FORMAT=text ;;
      *)
        echo "usage: clp [--image|--text]" >&2
        exit 2
        ;;
    esac

    # WSL only forwards explicitly listed Linux environment variables to Windows processes.
    export WSLENV="CLP_FORMAT''${WSLENV:+:''${WSLENV}}"

    # PowerShell expands the variables in this intentionally single-quoted shell argument.
    # shellcheck disable=SC2016
    exec powershell.exe -NoLogo -NoProfile -NonInteractive -STA -Command '
      $ErrorActionPreference = "Stop"
      Add-Type -AssemblyName System.Windows.Forms
      Add-Type -AssemblyName System.Drawing

      $format = $env:CLP_FORMAT
      $stdout = [Console]::OpenStandardOutput()

      if (($format -eq "auto" -or $format -eq "image") -and [System.Windows.Forms.Clipboard]::ContainsImage()) {
        $image = [System.Windows.Forms.Clipboard]::GetImage()
        $stream = New-Object System.IO.MemoryStream
        try {
          $image.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
          $bytes = $stream.ToArray()
        } finally {
          $stream.Dispose()
          $image.Dispose()
        }
      } elseif (($format -eq "auto" -or $format -eq "text") -and [System.Windows.Forms.Clipboard]::ContainsText()) {
        $text = [System.Windows.Forms.Clipboard]::GetText()
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        $bytes = $utf8.GetBytes($text)
      } else {
        if ($format -eq "image") {
          [Console]::Error.WriteLine("clp: Windows clipboard does not contain an image")
        } elseif ($format -eq "text") {
          [Console]::Error.WriteLine("clp: Windows clipboard does not contain text")
        } else {
          [Console]::Error.WriteLine("clp: Windows clipboard contains neither an image nor text")
        }
        exit 1
      }

      $stdout.Write($bytes, 0, $bytes.Length)
      $stdout.Flush()
    '
  '';

  meta = {
    description = "Write Windows clipboard image or text bytes to standard output from WSL";
    mainProgram = "clp";
    platforms = lib.platforms.linux;
  };
}
