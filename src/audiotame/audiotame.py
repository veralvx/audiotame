import sys


max_db = float(sys.argv[1])
limit_db = float(sys.argv[2])
difference = limit_db - max_db

if max_db < limit_db:
    result = "+" + str(difference)
    result = result.replace("++", "+")
else:
    result = "-" + str(difference)
    result = result.replace("--", "-")


result = "{:.2f}".format(float(result))

sys.exit(result)