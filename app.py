import ffmpeg
import cv2

input_video = "./media/sample_vid1.mp4"
output_pattern = "./media/frames/frame_%04d.png" # Output directory and file naming pattern

(
    ffmpeg
    .input(input_video) # Capture one frame every second
    .output(output_pattern, vf = "fps=1")
    .run()
)

# To find the fps of a vidoe
def get_video_fps(video_path):
    """
    Retrieves the FPS of a given video file using OpenCV.

    Args:
        video_path (str): The path to the video file.

    Returns:
        float: The FPS of the video, or -1.0 if the video cannot be opened.
    """
    cap = cv2.VideoCapture(video_path)

    if not cap.isOpened():
        print(f"Error: Could not open video file at {video_path}")
        return -1.0

    fps = cap.get(cv2.CAP_PROP_FPS)
    cap.release()
    return fps

fps_val = get_video_fps(input_video)

if fps_val != -1.0:
    print(f"The FPS of '{input_video}' is: {fps_val}")