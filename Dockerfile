# For Hugging Face:

FROM python:3.13

RUN apt update && apt upgrade -y
RUN apt install bash coreutils ffmpeg sox mp3gain -y
RUN apt autoremove -y && apt clean && rm -rf /var/lib/apt/lists

RUN python3 -m pip install --no-cache-dir --upgrade pip 
RUN python3 -m pip install --no-cache-dir audiotame[gui]
RUN useradd -m -u 1000 user
USER user
# Set home to the user's home directory
ENV HOME=/home/user \
	PATH=/home/user/.local/bin:$PATH

WORKDIR /app

EXPOSE 7860
ENV GRADIO_SERVER_NAME="0.0.0.0"
CMD ["audiotame", "--gradio"]

    