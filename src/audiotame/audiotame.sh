#!/bin/bash


# TODO
# ffmpeg -i output6.wav -af "highpass=f=80, lowpass=f=10000" outputter2.wav
# regular denoise with lopass and highpass
# generate noise profile for sox



#sox "$INPUT" "low_noise.wav" lowpass "$LOW_THRESHOLD"
#sox "low_noise.wav" -n noiseprof "low.prof"
#sox "$INPUT" "high_noise.wav" highpass "$HIGH_THRESHOLD
#sox "high_noise.wav" -n noiseprof "high.prof"
#sox "$INPUT" "temp.wav" noisered "low.prof" 0.21
#sox "temp.wav" "$OUTPUT" noisered "high.prof" 0.21
#rm "low_noise.wav" "high_noise.wav" "low.prof" "high.prof" "temp.wav"

#ffmpeg -i input.wav -af "treble=g=-6:f=10000" output.wav
#ffmpeg -i input.wav -af "bass=g=-6:f=100" output.wav

# Frequency Tweak
# Dividir em: sox_db_denoise, sox_frequency_denoise, regular_db_denoise, regular_frequency_denoise, highpass/lowpass (cut entirely)


audiotame_script_dir=$(dirname $(realpath $0))

if [ -z "$1" ];  then
    echo "insufficient numbers of arguments"
	echo "Usage: audiotame path_to_file" 
	exit
elif [[ $1 == "help" ]] || [[ $1 == "--help" ]] || [[ $1 == "-h" ]]; then

    echo """Usage: audiotame {path_to_file | --gradio} [operation] [operation_arg]

Flag:
  --gradio                Start Gradio server

Operations:
  pass                    Do not alter peak level db
  stats                   Display audio file statistics
  acx                     Check for ACX compatibility
  sr <sample_rate>        Change sample rate (e.g., 44100)
  br <bitrate>            Change bitrate (e.g., 128k, 320k)
  convert <format>        Convert to specified format (e.g., mp3, wav)
  extract                 Extract audio from video
"""

elif [[ "$1" == "--gradio" ]]; then
    python3 $audiotame_script_dir/app.py
    exit 1
elif ! [[ -f "$1" ]]; then 
    echo "File not found: $1"
    exit
fi


audio_dir=$(dirname $(realpath $1))
kitten_audio=$(realpath $1) # may have its db level tweaked or not.
base_name_input_file=$(basename $1)
base_name_no_ext=${base_name_input_file%.*}
input_extension="${1##*.}"
input_extension=$(echo "$input_extension" | tr '[:upper:]' '[:lower:]')
real_pwd=$(realpath .)


if [[ $GRADIO_RUNNING -ne 1 ]]; then

    CONVERT_LOSSY_TO_WAV=1
    DB_PEAK_BEFORE_ALL="-100"
    DB_PEAK_AFTER_NORM="-100"
    TRUE_PEAK="-3"
    NORM_TYPE="ebu"
    LOUD_TARGET="-21"
    ARNNDN=0
    ARNNDN_MODEL="cb.rnnn"
    SOX_DENOISE=1
    SOX_FACTOR=0.21
    SOX_NOISE_THRESHOLD="-50"
    SOX_NOISE_MIN_DURATION=0.5
    REGULAR_DENOISE=1
    REGULAR_NOISE_THRESHOLD="-50"
    SILENCE_FLOOR="-60"
    DEBUG=0


    if [[ -f $real_pwd/audiotame.env ]]; then
        source $real_pwd/audiotame.env
    elif [[ -f $real_pwd/.env.audiotame ]]; then
        source $real_pwd/.env.audiotame 
    elif [[ -f $real_pwd/.env ]]; then 
        source $real_pwd/.env 
    else
        if [[ -f $HOME/.env.audiotame ]]; then
            source $HOME/.env.audiotame
        elif [[ -f $HOME/audiotame.env ]]; then
            source $HOME/audiotame.env
        elif [[ -f $HOME/.config/.env.audiotame ]]; then
            source $HOME/.config/.env.audiotame
        elif [[ -f $HOME/.config/audiotame.env ]]; then
            source $HOME/.config/audiotame.env
        fi
    fi

fi


stats(){
    LUFS=$(ffmpeg -i $1 -af ebur128=framelog=verbose -f null - 2>&1 | awk '/I:/{print $2}')
    RMS=$(ffmpeg -i $1 -af astats=metadata=1:reset=0:measure_perchannel=0 -f null - 2>&1 | grep "RMS level" | cut -d ":" -f 2)
    PEAK=$(ffmpeg -i $1 -af volumedetect -vn -f null - 2>&1 |  grep "max_volume" | cut -d ":" -f 2 | cut -d "d" -f 1)
    sampling_rate=$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 $1)

    if [[ $input_extension == "flac" ]]; then
        bit_rate=$(ffprobe -v error -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 $1)
    else
        bit_rate=$(ffprobe -v error -select_streams a:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 $1)
    fi
}

echo_stats(){
    echo """
LUFS: $LUFS
RMS: $RMS
Peak: $PEAK
Sampling Rate: $sampling_rate
Bit Rate: $bit_rate
"""
}


if [[ $(ffmpeg -encoders | grep libfdk_aac) ]]; then     
    aac_encoder="libfdk_aac"
    aac_options="-cutoff 20000 -afterburner 1 -vbr 5"
    echo "here in grep"
else     
    aac_encoder="aac"
    aac_options="-b:a 320k"
fi 



if [[ "$2" == "acx" ]]; then

    stats $kitten_audio
    python3 $audiotame_script_dir/acx.py "$base_name_input_file" "$LUFS" "$RMS" "$PEAK" "$sampling_rate" "$bit_rate"
    exit

elif [[ "$2" == "stats" ]]; then

    stats $kitten_audio
    echo_stats
    exit

elif [[ "$2" == "convert" ]]; then

    if [ -z "$3" ]; then
        echo "output format not specified."
        echo "usage: audiotame path_to_audio convert output_format"
        echo "example: audiotame audio.wav convert mp3"
  
    elif [[ "$3" == "mp3" ]]; then
        ffconvargs="-qscale:a 0"
    elif [[ "$3" == "ogg" ]]; then
        ffconvargs="-qscale:a 10"
    elif [[ "$3" == "flac" ]]; then
        ffconvargs="-compression_level 12"
    elif [[ "$3" == "aac" ]]; then

    	ffconvargs="-c:a $aac_encoder $aac_options" 

    else
        ffconvargs=""
    fi

    # wav, flac, m4a, aac, aiff, mp3, ogg, opus, wma

    if [[  "$input_extension" == "$3" ]]; then
        echo "input_extension is equal to conversion target. Skipping..."
    else
        ffmpeg -i $kitten_audio $ffconvargs $audio_dir/$base_name_no_ext.$3 -y
    fi
        
    exit

elif [[ "$2" == "extract" ]]; then

    codec=$(ffprobe -v error -select_streams a:0 \
    -show_entries stream=codec_name \
    -of default=noprint_wrappers=1:nokey=1 "$kitten_audio")

    ffmpeg -i "$kitten_audio" -vn -c:a copy $audio_dir/$base_name_no_ext.$codec -y

    echo "Extracted audio, saved as $audio_dir/$base_name_no_ext.$codec"

    exit

fi


codec_option=-c:a
if [[ $input_extension == "ogg" ]]; then
    codec_lib=libvorbis
elif [[ $input_extension == "flac" ]]; then
    codec_lib=flac
elif [[ $input_extension == "m4a" ]]; then
    codec_lib=aac
elif [[ $input_extension == "opus" ]] || [[ $input_extension == "webm" ]]; then
    codec_lib=libopus
elif [[ $input_extension == "aac" ]]; then
    codec_lib="$aac_encoder"
else
    codec_option=""
    codec_lib=""
fi



if [[ $CONVERT_LOSSY_TO_WAV -eq 1 ]]; then

    lossy_formats=("mp3" "aac" "m4a" "ogg" "opus" "wma" "webm")
    is_lossy=0

    for fmt in "${lossy_formats[@]}"; do
        if [[ "$input_extension" == "$fmt" ]]; then
            is_lossy=1
            echo "Detected lossy format ($input_extension)"
            break
        fi
    done

    if [[ "$is_lossy" -eq 1 ]]; then

        echo "Converting to wav: $kitten_audio"
        ffmpeg -i "$kitten_audio" "$audio_dir/.$base_name_no_ext-lossy2wav.wav" -y

        if [[ -f "$audio_dir/.$base_name_no_ext-lossy2wav.wav" ]]; then
            input_extension="wav"
            kitten_audio="$audio_dir/.$base_name_no_ext-lossy2wav.wav"
            echo "$kitten_audio created"
        else
            echo "Conversion Failed. Using $kitten_audio"
        fi

    else 
        echo "The file format $input_extension is not recognized as lossy. No conversion performed."
    fi
fi


if [[ "$2" == "sr" ]]; then

    if [[ "$3" =~ [[:alpha:]] ]] || [[ "$3" == *.* ]]; then
        echo "Example usage: audiotamer audio.wav sr 44100"
        exit
    fi

    if [[ -f $audio_dir/$base_name_no_ext-$3hz.$input_extension ]]; then rm $audio_dir/$base_name_no_ext-$3hz.$input_extension; fi
    ffmpeg -i "$kitten_audio" -ar $3 $audio_dir/$base_name_no_ext-$3hz.$input_extension
    exit

elif [[ "$2" == "br" ]]; then

    if [[ "$3" != *k* ]] || [[ "$3" == *.* ]]; then
        echo "Example usage: audiotamer audio.wav br 192k"
        exit
    fi

    if [[ -f $audio_dir/$base_name_no_ext-$3kbps.$input_extension ]]; then rm -f $audio_dir/$base_name_no_ext-$3kbps.$input_extension; fi
    ffmpeg -i $kitten_audio -b:a $3 $audio_dir/$base_name_no_ext-$3bps.$input_extension
    exit

elif [ -z "$2" ]; then

    if [[ "$DB_PEAK_BEFORE_ALL" -ne "-100" ]]; then
        ffmpeg_db_limit=$DB_PEAK_BEFORE_ALL
    else
        echo "ffmpeg_db_limit before all functions not set. Passing."
        ffmpeg_db_limit="pass"
    fi

else
    ffmpeg_db_limit="$2"
fi


echo """env vars:
CONVERT_LOSSY_TO_WAV=$CONVERT_LOSSY_TO_WAV
DB_PEAK_BEFORE_ALL=$DB_PEAK_BEFORE_ALL
DB_PEAK_AFTER_NORM=$DB_PEAK_AFTER_NORM
NORM_TYPE="$NORM_TYPE"
LOUD_TARGET=$LOUD_TARGET
ARNNDN=$ARNNDN
ARNNDN_MODEL=$ARNNDN_MODEL
SOX_DENOISE=$SOX_DENOISE
SOX_FACTOR=$SOX_FACTOR
SOX_NOISE_THRESHOLD=$SOX_NOISE_THRESHOLD
SOX_NOISE_MIN_DURATION=$SOX_NOISE_MIN_DURATION
REGULAR_DENOISE=$REGULAR_DENOISE
REGULAR_NOISE_THRESHOLD=$REGULAR_NOISE_THRESHOLD
SILENCE_FLOOR=$SILENCE_FLOOR
DEBUG=$DEBUG
"""



db_tweak(){

    if [[ -f $audio_dir/.$base_name_no_ext-dbtweak.$input_extension ]]; then rm $audio_dir/.$base_name_no_ext-dbtweak.$input_extension; fi

    if [[ $ffmpeg_db_limit == "pass" ]]; then
        :
    else
        current_peak="$(ffmpeg -i "$1" -af volumedetect -vn -f null - 2>&1 |  grep "max_volume" | cut -d ":" -f 2 | cut -d "d" -f 1)"
        echo "Current peak: $current_peak"
        python_output=$((python3 $audiotame_script_dir/audiotame.py $current_peak "$ffmpeg_db_limit") 2>&1)
        echo "Must add: $python_output"
        ffmpeg -i "$1" -af volume=${python_output}dB $audio_dir/.$base_name_no_ext-dbtweak.$input_extension -y
        current_peak=$(ffmpeg -i $audio_dir/.$base_name_no_ext-dbtweak.$input_extension -af volumedetect -vn -f null - 2>&1 |  grep "max_volume" | cut -d ":" -f 2 | cut -d "d" -f 1)
        
       # V=""
       # formatted_ffmpeg_db_limit=$(printf "%.1f" "$ffmpeg_db_limit")
       # echo "$formatted_ffmpeg_db_limit"
       # exit

       # while [[ "$current_peak" != "$formatted_ffmpeg_db_limit" ]]; do
       #     Vt="$V-V"
       #     python_output=$((python3 $audiotame_script_dir/audiotame.py $current_peak "$ffmpeg_db_limit") 2>&1)
       #     ffmpeg -i "$audio_dir/.$base_name_no_ext-dbtweak$V.$input_extension" -af volume=${python_output}dB -c:v copy $audio_dir/.$base_name_no_ext-dbtweak$Vt.$input_extension -y
       #     current_peak=$(ffmpeg -i $audio_dir/.$base_name_no_ext-dbtweak$Vt.$input_extension -af volumedetect -vn -f null - 2>&1 |  grep "max_volume" | cut -d ":" -f 2 | cut -d "d" -f 1)
       #     V="$Vt"
       # done

        
    fi


    if [[ -f $audio_dir/.$base_name_no_ext-dbtweak.$input_extension ]]; then
        kitten_audio=$audio_dir/.$base_name_no_ext-dbtweak.$input_extension
        echo "$kitten_audio created"
    fi

    
}


db_tweak $kitten_audio


if [[ $DEBUG -eq 1 ]]; then
    stats "$kitten_audio"
    echo_stats
fi

# Noise is below 50db, for at least 0.5s


if [[ $SOX_DENOISE -eq 1 ]]; then

    if [[ $input_extension == "webm" ]]; then
        ffmpeg -i $kitten_audio $audio_dir/.$base_name_no_ext-webm2wav.wav -y
        kitten_audio="$audio_dir/.$base_name_no_ext-webm2wav.wav"
    elif [[ $input_extension == "opus" ]]; then
        ffmpeg -i $kitten_audio $audio_dir/.$base_name_no_ext-opus2wav.wav -y
        kitten_audio=$audio_dir/.$base_name_no_ext-opus2wav.wav
    fi

    if [[ $input_extension == "webm" ]] || [[ $input_extension == "opus" ]]; then
        input_extension=wav
        codec_option=""
        codec_lib=""
    fi


    # Not Working:
    #if [[ CUT_NOISE_START -eq 1 ]]; then
    #    ffmpeg -i "$kitten_audio" -af "silenceremove=start_periods=1:start_duration=0:start_threshold=${NOISE_THRESHOLD}dB" $audio_dir/.$base_name_no_ext-cutstart.$input_extension
    #   kitten_cut="$audio_dir/.$base_name_no_ext-cutstart.$input_extension"
    #else
    #    kitten_cut="$kitten_audio"
    #fi

    #if [[ CUT_NOISE_END -eq 1 ]]; then
    #    ffmpeg -i $kitten_cut -af "silenceremove=stop_periods=1:stop_duration=0:stop_threshold=${NOISE_THRESHOLD}dB" $audio_dir/.$base_name_no_ext-cutend.$input_extension
    #    kitten_cut=$audio_dir/.$base_name_no_ext-cutend.$input_extension
    #fi


    # Run ffmpeg with silencedetect and capture stderr output
    ffmpeg_output=$(ffmpeg -i "$kitten_audio" -af "silencedetect=noise=${SOX_NOISE_THRESHOLD}dB:d=${SOX_NOISE_MIN_DURATION}" -f null - 2>&1)

    # Parse silence start and end times into arrays
    readarray -t silence_start_array < <(echo "$ffmpeg_output" | grep "silence_start" | sed -E 's/.*silence_start: ([0-9.]+).*/\1/')
    readarray -t silence_end_array   < <(echo "$ffmpeg_output" | grep "silence_end"   | sed -E 's/.*silence_end: ([0-9.]+).*/\1/')

    # Build filter_complex string for trimming and concatenating noise segments
    filter_complex=""
    concat_inputs=""


    num_segments=${#silence_start_array[@]}
    if [ $num_segments -gt 0 ]; then

        echo "Noise segments detected: $num_segments"

        for index in "${!silence_start_array[@]}"; do
            start_time=${silence_start_array[$index]}
            end_time=${silence_end_array[$index]}
            filter_complex+="[0:a]atrim=start=${start_time}:end=${end_time},asetpts=PTS-STARTPTS[x${index}]; "
            concat_inputs+="[x${index}]"
        done

        filter_complex+="${concat_inputs}concat=n=${num_segments}:v=0:a=1[noise]"
        echo "Constructed filter_complex: $filter_complex"

        ffmpeg -i "$kitten_audio" -filter_complex "$filter_complex" -map "[noise]" ".$base_name_no_ext-noise.$input_extension" -y

        sox ".$base_name_no_ext-noise.$input_extension" -n noiseprof ".$base_name_no_ext-noise.prof"
        sox "$kitten_audio" ".$base_name_no_ext-denoised.$input_extension" noisered ".$base_name_no_ext-noise.prof" "$SOX_FACTOR"

        echo "Denoising complete. Output saved to .${base_name_no_ext}-denoised.${input_extension}"

    else
        echo "No noise segments detected."
    fi
else
    echo "SOX_DENOISE is $SOX_DENOISE"
    echo "input_extension is $input_extension"
    echo "Not applying sox denoising"
fi


if [[ -f .$base_name_no_ext-denoised.$input_extension ]]; then
    kitten_sox=".$base_name_no_ext-denoised.$input_extension"
else
    echo "No sox denoised file detected"
    kitten_sox=$kitten_audio
fi


if [[ $REGULAR_DENOISE -eq 1 ]]; then
    # everything below 50db gets reduced in 10db
    ffmpeg -i $kitten_sox -af "afftdn=nr=10:nf=$REGULAR_NOISE_THRESHOLD" $audio_dir/.$base_name_no_ext-afftdn.$input_extension -y


    if [[ $DEBUG -eq 1 ]]; then
        stats "$audio_dir/.$base_name_no_ext-afftdn.$input_extension"
        echo_stats
    fi


    # it seems this has no effect. Review later
    ffmpeg -i $audio_dir/.$base_name_no_ext-afftdn.$input_extension -af silenceremove=0:1:${SILENCE_FLOOR}dB "$audio_dir/.$base_name_no_ext-nosilence.$input_extension" -y


    if [[ $DEBUG -eq 1 ]]; then
        stats "$audio_dir/.$base_name_no_ext-nosilence.$input_extension"
        echo_stats
    fi
else
    echo "REGULAR_DENOISE is $REGULAR_DENOISE."
    echo "input_extension is $input_extension"
    echo "Not applying regular denoising filters."

fi



if [[ -f "$audio_dir/.$base_name_no_ext-nosilence.$input_extension" ]]; then
    kitten_noise="$audio_dir/.$base_name_no_ext-nosilence.$input_extension"
    echo "$kitten_noise created"
else
    kitten_noise="$kitten_sox"
fi



# May re-sample to 48khz
echo "ARNNDN variable is $ARNNDN"
if [[ $ARNNDN -eq 1 ]]; then
    ffmpeg -i $kitten_noise -af arnndn=m=$audiotame_script_dir/arnndn-models/$ARNNDN_MODEL "$audio_dir/.$base_name_no_ext-arnndn.$input_extension" -y
fi


if [[ -f "$audio_dir/.$base_name_no_ext-arnndn.$input_extension" ]]; then
    kitten_prenorm="$audio_dir/.$base_name_no_ext-arnndn.$input_extension"
    echo "$kitten_prenorm created"
else
    kitten_prenorm=$kitten_noise
fi


if [[ $DEBUG -eq 1 ]]; then
    stats "$kitten_prenorm" 
    echo_stats
fi


if [[ $input_extension == "mp3" ]]; then
    cp "$kitten_prenorm" $audio_dir/.$base_name_no_ext-normalized.$input_extension
    mp3gain -r -c $audio_dir/.$base_name_no_ext-normalized.$input_extension
else
    # ffmpeg-normalize sometimes re-samples to 192khz
    echo "Loudness target: $LOUD_TARGET"
    echo "Normalization type: $NORM_TYPE"
    ffmpeg-normalize -f "$kitten_prenorm" -nt "$NORM_TYPE" -t "$LOUD_TARGET" $codec_option $codec_lib  --true-peak $TRUE_PEAK -o "$audio_dir/.$base_name_no_ext-normalized.$input_extension" 

fi


if [[  -f "$audio_dir/.$base_name_no_ext-normalized.$input_extension" ]]; then
    kitten_norm="$audio_dir/.$base_name_no_ext-normalized.$input_extension"
    echo "$audio_dir/.$base_name_no_ext-normalized.$input_extension created"
else
    kitten_norm=$kitten_prenorm
fi


if [[ $DEBUG -eq 1 ]]; then
    echo "CODECS: $codec_option $codec_lib"
    stats "$kitten_norm"
    echo_stats  
fi

if [ -z "$3" ]; then

    if [[ "$DB_PEAK_AFTER_NORM" -ne "-100" ]]; then
        ffmpeg_db_limit=$DB_PEAK_AFTER_NORM
    else
        echo "ffmpeg_db_limit after normalization not set. Passing."
        ffmpeg_db_limit="pass"
    fi 
#    ffmpeg_db_limit="-5.0"
else
    ffmpeg_db_limit="$3"
fi


db_tweak "$kitten_norm"

if [[ -f $audio_dir/.$base_name_no_ext-dbtweak.$input_extension ]]; then mv $audio_dir/.$base_name_no_ext-dbtweak.$input_extension $kitten_norm; fi

mv $kitten_norm $audio_dir/$base_name_no_ext-tamed.$input_extension

echo "$audio_dir/$base_name_no_ext-tamed.$input_extension created"

stats $audio_dir/$base_name_no_ext-tamed.$input_extension
echo_stats

# Cleaning

for i in $(find . -type f \( -name "\.$base_name_no_ext*\.$input_extension" -o -name "\.$base_name_no_ext*.prof" \)); do
    rm "$i"
done