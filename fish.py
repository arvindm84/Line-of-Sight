from fishaudio import FishAudio
from fishaudio.utils import save
import generate_audio_script

# Initialize with your API key
client = FishAudio(api_key="b34f820bdc61448e96e1235f94fa60d0") # Sreevatsa's API KEY

response = generate_audio_script.gemini_text()

print(response)

# Generate speech
audio = client.tts.convert(text=response)
save(audio, "welcome.mp3")

print("✓ Audio saved to welcome.mp3")

