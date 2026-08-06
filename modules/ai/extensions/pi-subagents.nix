{ ... }:
{
  # pi-subagents — async subagent delegation with truncation, artifacts,
  # session sharing, and bundled agent skills/prompts.
  # https://github.com/nicobailon/pi-subagents
  pi.extensions.pi-subagents = {
    pname = "pi-subagents";
    version = "0.41.0";
    hash = "sha512-FI1qgz93cCgdeV9TpkypYNlBXVw7Xel18ooIFtWwgSMnGsCmWD71UkadADynAIhQIEwGX9B4j0udfUHySXkSKQ==";
    vendor = [
      {
        dir = "jiti";
        pname = "jiti";
        version = "2.7.0";
        hash = "sha512-AC/7JofJvZGrrneWNaEnJeOLUx+JlGt7tNa0wZiRPT4MY1wmfKjt2+6O2p2uz2+skll8OZZmJMNqeke7kKbNgQ==";
      }
      {
        dir = "typebox";
        pname = "typebox";
        version = "1.1.38";
        hash = "sha512-pZ0aQPmMmXoUvSbeuWf/Hzsc+avNw/Zd6VeE8CFgkVGWyuHPJvqeJJDeJqLve+K70LvjYIoleGcoJHPT17cWoA==";
      }
      {
        dir = "yaml";
        pname = "yaml";
        version = "2.8.3";
        hash = "sha512-AvbaCLOO2Otw/lW5bmh9d/WEdcDFdQp2Z2ZUH3pX9U2ihyUY0nvLv7J6TrWowklRGPYbB/IuIMfYgxaCPg5Bpg==";
      }
    ];
  };
}
