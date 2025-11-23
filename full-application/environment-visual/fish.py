from fishaudio import FishAudio
#from fishaudio.utils import save, play
import os
from dotenv import load_dotenv


def get_fish_audio(response):
    """Convert text response to speech using Fish Audio API.
    
    Args:
        response: Text to convert to speech
        
    Returns:
        tuple: (output1_path, output2_path) or (None, None) on error
    """
    load_dotenv()  # Load the .env for API Keys

    response = str(response)  # Make sure the response is a string

    # Initialize with your API key
    api_key = os.getenv("FISH_AUDIO_API_KEY")
    if not api_key:
        print("Error: FISH_AUDIO_API_KEY not found in environment")
        return None, None
        
    client = FishAudio(api_key=api_key)

    # # Generate speech
    # audio = client.tts.convert(
    #     text=response,
    #     reference_id="8ef4a238714b45718ce04243307c57a7"
    #     )
    # save(audio, "welcome.mp3")

    # print("✓ Audio saved to welcome.mp3")

    audio_parts = response.split(".")

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

    # Ensure audio directory exists
    audio_dir = os.path.join(os.path.dirname(__file__), "media", "audio")
    os.makedirs(audio_dir, exist_ok=True)
    
    output1_path = os.path.join(audio_dir, "output1.mp3")
    output2_path = os.path.join(audio_dir, "output2.mp3")
    
    # Clean up old audio files if they exist
    for path in [output1_path, output2_path]:
        if os.path.exists(path):
            os.remove(path)
            print(f"Removed old audio file: {path}")

    # Stream directly to file (memory efficient for large audio)
    audio_stream1 = client.tts.stream(text=first_part, reference_id="bf322df2096a46f18c579d0baa36f41d")

    # Converting text to speech using fish audio with the first part
    with open(output1_path, "wb") as f:
        for chunk in audio_stream1:
            f.write(chunk)  # Write each chunk as it arrives
    
    print(f"✓ Audio part 1 saved to {output1_path}")

    # Stream directly to file (memory efficient for large audio)
    audio_stream2 = client.tts.stream(text=second_part, reference_id="bf322df2096a46f18c579d0baa36f41d")

    # Converting text to speech using fish audio with the second part
    with open(output2_path, "wb") as f:
        for chunk in audio_stream2:
            f.write(chunk)  # Write each chunk as it arrives
    
    print(f"✓ Audio part 2 saved to {output2_path}")
    
    return output1_path, output2_path