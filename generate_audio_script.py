from google import genai
from PIL import Image
import os
from dotenv import load_dotenv
import fish

def gemini_text():

    load_dotenv()

    gemini_api = os.getenv("GEMINI_API_KEY")

    sample_image_path = './media/frames/frame_0001.png'

    # Load the image using the Pillow (PIL) library
    sample_image = Image.open(sample_image_path)

    # The client gets the API key from the environment variable `GEMINI_API_KEY`.
    client = genai.Client(api_key=gemini_api)

    prompt = """"You are a highly perceptive and efficient descriptive guide. Your task is 
    to provide a real-time, evocative audio description of the user's immediate surroundings. 
    The description must be delivered in a factual, stylish, and engaging manner, focusing 
    strictly on objects and elements that define the space.
    The entire description must be extremely concise—no more than a few seconds of spoken 
    word—to keep pace with the user's continuous movement.
    Describe the most striking, movable, or defining elements in the foreground (within three 
    steps) and the middle distance (up to 15 steps). Focus on textures, dominant colors, 
    and distinctive shapes of objects, people, or structures. Conclude with a single, 
    memorable summary of the current ambient feeling or setting (e.g., 'A lively outdoor 
    market,' 'The solemn geometry of office buildings'). Do NOT mention the weather, sky, or 
    any safety/navigational concerns.

    If I have given you an image before and it is basically the same frame with very few changes 
    (like as if the user walked only a few steps ahead), then make a general comment, return 
    lesser text than usual and dont menton things you have mentioned before like how a 
    particular thing looks."""

    response = client.models.generate_content(
        model="gemini-2.5-flash", 
        # contents="What is the difference between a partial order relation and other relations"
        contents=[
            sample_image,
            prompt
        ]
    )
    
    fish.get_fish_audio(response=response)
