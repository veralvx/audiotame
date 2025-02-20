import os
import subprocess
import sys
import shutil

def main():

    input_file = sys.argv[1]

    if " " in input_file:
        new_file = input_file.replace(" ", "")
        if os.path.exists(new_file):
            os.remove(new_file)
        shutil.copyfile(input_file, new_file)
        sys.argv[1] = new_file

    script = os.path.join(os.path.dirname(__file__), "audiotame.sh")

    if not os.path.exists(script):
        sys.exit("Cannot find audiotame.sh")

    subprocess.run(["bash", script] + sys.argv[1:], check=True)

if __name__ == "__main__":
    main()


