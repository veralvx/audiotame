import sys

basename_file = sys.argv[1]
LUFS = float(sys.argv[2])
RMS = float(sys.argv[3])
PEAK = float(sys.argv[4])
FREQUENCY = float(sys.argv[5])
BIT_RATE = float(sys.argv[6])

#success="\033[32m✓\033[0m"
success="✓"
failure="✗"

def print_line(parameter, name, acx, status):
    print("{:<10}  {:^20}  {:^20}  {:^20}".format(parameter, name, acx, status))



def main():
    print_line("Parameter", basename_file, "ACX", "Status")


    #  -23db < LUFS and RMS < -18db
    if -23 < LUFS < -18:
        status = success
    else:
        status = failure

    print_line("LUFS", LUFS, '-23db < LUFS < -18db', status)


    if -23 < RMS < -18:
        status = success
    else:
        status = failure

    print_line("RMS", RMS, '-23db < RMS < -18db', status)


    # Peak <= -3db
    if PEAK <= -3:
        status = success
    else:
        status= failure

    print_line("Peak", PEAK, 'Peak <= -3db', status)


    # Frequency == 44.1khz
    if FREQUENCY == 44100 or FREQUENCY == 44100.0:
        status = success
    else:
        status = failure

    print_line("Frequency", FREQUENCY, 'Frequency == 44.1khz', status)

    # Bit rate >= 192kbs
    if BIT_RATE >= 192000:
        status = success
    else:
        status = failure

    print_line("Bit Rate", BIT_RATE, 'Bit Rate >= 192kbs', status)


if __name__ == "__main__":
    main()
