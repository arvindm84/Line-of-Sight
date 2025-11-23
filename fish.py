from fishaudio import FishAudio
from fishaudio.utils import save
import generate_audio_script
import os
from dotenv import load_dotenv


def get_fish_audio(response):
    load_dotenv()

    # Initialize with your API key
    client = FishAudio(api_key=os.getenv("FISH_AUDIO_KEY")) # Sreevatsa's API KEY

    # # Generate speech
    # audio = client.tts.convert(
    #     text=response,
    #     reference_id="8ef4a238714b45718ce04243307c57a7"
    #     )
    # save(audio, "welcome.mp3")

    # print("✓ Audio saved to welcome.mp3")


    # Stream directly to file (memory efficient for large audio)
    audio_stream = client.tts.stream(text=response)
    with open("audio/output.mp3", "wb") as f:
        for chunk in audio_stream:
            f.write(chunk)  # Write each chunk as it arrives

    #The above is still waiting for the entire file to be done before making output.mp3