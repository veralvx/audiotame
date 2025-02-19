import os
import subprocess
import sys


def main():
    script = os.path.join(os.path.dirname(__file__), "audiotame.sh")

    if not os.path.exists(script):
        sys.exit("Cannot find audiotame.sh")

    subprocess.run(["bash", script] + sys.argv[1:], check=True)

if __name__ == "__main__":
    main()


