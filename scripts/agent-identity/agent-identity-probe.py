# agent-identity-probe: fixed, side-effect-free probes for agent-identity-verify.
#
# Run by the owner as the agent through sudo (the only command, besides the
# agent's login shell and agent-enter, that sudoers lets anyone run as the
# agent). It executes nothing else and imports only the standard library; the
# interpreter runs with -I (isolated: no user site-packages, no PYTHON*
# environment, no current directory on sys.path), so nothing the agent can
# write (its home, .pth files, profile, PATH) is loaded.
#
#   agent-identity-probe id                    -> uid
#   agent-identity-probe netns                 -> net:[...] of this process
#   agent-identity-probe tcp <host> <port>     -> CONNECTED|REFUSED|EACCES|TIMEOUT|<errno>
#   agent-identity-probe unix <path>           -> same, AF_UNIX path socket
#   agent-identity-probe abstract <name>       -> same, abstract socket
#   agent-identity-probe access <path>         -> READABLE|EACCES|NOENT|<errno>
import errno
import os
import socket
import sys


def connect(kind, target, port=None):
    try:
        if kind == "tcp":
            s = socket.create_connection((target, int(port)), timeout=4)
        else:
            s = socket.socket(socket.AF_UNIX)
            s.settimeout(4)
            s.connect(target if kind == "unix" else "\0" + target)
        s.close()
        return "CONNECTED"
    except socket.timeout:
        return "TIMEOUT"
    except OSError as e:
        return {errno.ECONNREFUSED: "REFUSED", errno.EACCES: "EACCES", errno.EPERM: "EACCES",
                errno.ENOENT: "NOENT"}.get(e.errno, errno.errorcode.get(e.errno, str(e.errno)))


def access(path):
    try:
        if os.path.isdir(path):
            os.listdir(path)
        else:
            with open(path, "rb"):
                pass
        return "READABLE"
    except OSError as e:
        return {errno.EACCES: "EACCES", errno.EPERM: "EACCES", errno.ENOENT: "NOENT",
                errno.ENXIO: "NOT-A-FILE"}.get(e.errno, errno.errorcode.get(e.errno, str(e.errno)))


def main(argv):
    if argv[:1] == ["id"] and len(argv) == 1:
        return str(os.getuid())
    if argv[:1] == ["netns"] and len(argv) == 1:
        return os.readlink("/proc/self/ns/net")
    if argv[:1] == ["tcp"] and len(argv) == 3:
        return connect("tcp", argv[1], argv[2])
    if argv[:1] in (["unix"], ["abstract"]) and len(argv) == 2:
        return connect(argv[0], argv[1])
    if argv[:1] == ["access"] and len(argv) == 2:
        return access(argv[1])
    sys.stderr.write("usage: agent-identity-probe id|netns|tcp HOST PORT|unix PATH|abstract NAME|access PATH\n")
    sys.exit(2)


print(main(sys.argv[1:]))
