from google import genai
from PIL import Image

def gemini_text():
    GEMINI_API_KEY = 'AIzaSyCc9aGSvySxbPGd2tHT0kem-CXqxISH3a0'

    sample_image_path = './media/frames/frame_0001.png'

    # Load the image using the Pillow (PIL) library
    sample_image = Image.open(sample_image_path)

    # The client gets the API key from the environment variable `GEMINI_API_KEY`.
    client = genai.Client(api_key=GEMINI_API_KEY)

    prompt = """You are an attentive, practical, and highly detailed personal guide. Your task is to
            provide a real-time, functional audio description of the immediate environment captured
            in the image. The description must be clear, concise, actionable, and focused on spatial
            orientation, obstacles, and the immediate proximity of people or objects.
            Begin with the most critical safety information (e.g., ground level, major obstacles). 
            Then, describe the immediate foreground (within three steps), focusing on their location 
            relative to the viewer (e.g., 'to your left') and their potential use or hazard. 
            Conclude with the general setting and any notable ambient conditions (e.g., busy,
            quiet, light source). Don't be so descriptive, This text generated, when spoken out, 
            should be only a few seconds long because the user will continue walking farther."""

    response = client.models.generate_content(
        model="gemini-2.5-flash", 
        # contents="What is the difference between a partial order relation and other relations"
        contents=[
            sample_image,
            prompt
        ]
    )
    
    return response.text