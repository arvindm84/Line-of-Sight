from fishaudio import FishAudio
from fishaudio.utils import save
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

    audio_parts = audio_stream.split(".")

    # Check the length of the first part after splitting by space
    first_part = audio_parts[0]
    if len(first_part.split(" ")) < 5:
        # If the first part has fewer than 5 words, include the next part from the audio stream
        if len(audio_parts) > 1:
            first_part += "." + audio_parts[1]  # Append second part if it exists
        # Check if the combined first part is long enough
        if len(first_part.split(" ")) < 5 and len(audio_parts) > 2:
            # If still too short, include the third part
            first_part += "." + audio_parts[2]
        second_part = ".".join(audio_parts[3:]) if len(audio_parts) > 3 else ""  # Join any remaining parts
    else:
        # If the first part already has 5 or more words, use the second part as the second part
        second_part = ".".join(audio_parts[1:])  # Join the rest after the first part

    # Converting speech to text using fish audio with the first part and then the second
    with open("./media/output.mp3", "wb") as f:
        for chunk in audio_stream:
            f.write(chunk)  # Write each chunk as it arrives

    #The above is still waiting for the entire file to be done before making output.mp3