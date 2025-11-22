import cv2
import numpy as np
from ultralytics import YOLOWorld
from collections import defaultdict

# --- CONFIGURATION ---
DANGER_ZONE_RATIO = 0.4  # If object takes up 40% of screen height -> IMMEDIATE STOP
APPROACH_THRESHOLD = 0.02 # If object grows by 2% per frame -> APPROACHING FAST

class DangerAnalyzer:
    def __init__(self):
        # Store previous height of objects: {track_id: height}
        self.history = defaultdict(lambda: []) 

    def analyze(self, track_id, current_h, frame_h):
        """
        Returns: (status, message)
        Status: 'SAFE', 'WARNING', 'CRITICAL'
        """
        # 1. IMMEDIATE PROXIMITY CHECK (How big is it?)
        height_ratio = current_h / frame_h
        
        if height_ratio > DANGER_ZONE_RATIO:
            return "CRITICAL", "STOP! Object directly in front!"

        # 2. APPROACH SPEED CHECK (Is it getting bigger?)
        # We need at least 5 frames of history to judge speed
        self.history[track_id].append(current_h)
        if len(self.history[track_id]) > 10: 
            self.history[track_id].pop(0) # Keep list short

        if len(self.history[track_id]) >= 5:
            # Compare current size to size 5 frames ago
            past_h = self.history[track_id][0]
            growth = (current_h - past_h) / past_h
            
            if growth > APPROACH_THRESHOLD:
                return "WARNING", "Approaching fast"
        
        return "SAFE", ""

# --- MAIN SETUP ---
# Use a VIDEO file for testing 'approaching' (images won't work)
# Replace with the path to the video you download (link below)
video_source = r"C:\Users\Sreevatsa\Documents\GitHub\2D-3D-Modeling\YTDown.com_YouTube_4K-WALKING-THROUGH-THE-MOST-PACKED-CROWD_Media_F5o1mJZMOdQ_003_480p.mp4" 
cap = cv2.VideoCapture(video_source)

model = YOLOWorld('yolov8s-world.pt')
model.set_classes([
    "car", "bus", "truck", "cyclist", "pedestrian", 
    "pole", "tree", "construction barrier"
])

analyzer = DangerAnalyzer()

while True:
    ret, frame = cap.read()
    if not ret: break

    h, w, _ = frame.shape
    
    # USE 'TRACK' INSTEAD OF 'PREDICT'
    # persist=True keeps the ID #s consistent between frames
    results = model.track(frame, persist=True, conf=0.25, verbose=False)

    if results[0].boxes.id is not None:
        # Get the boxes and their unique IDs
        boxes = results[0].boxes.xyxy.cpu()
        track_ids = results[0].boxes.id.int().cpu().tolist()
        classes = results[0].boxes.cls.int().cpu().tolist()

        for box, track_id, cls in zip(boxes, track_ids, classes):
            x1, y1, x2, y2 = box
            obj_h = y2 - y1
            obj_name = model.names[cls]

            # ANALYZE DANGER
            status, message = analyzer.analyze(track_id, obj_h, h)

            # DRAW VISUALS
            color = (0, 255, 0) # Green (Safe)
            if status == "WARNING": color = (0, 255, 255) # Yellow
            if status == "CRITICAL": color = (0, 0, 255) # Red

            # Draw Box
            cv2.rectangle(frame, (int(x1), int(y1)), (int(x2), int(y2)), color, 2)
            
            # Draw Danger Label
            label = f"#{track_id} {obj_name}"
            if status != "SAFE":
                label += f" [{status}]"
            
            cv2.putText(frame, label, (int(x1), int(y1)-10), 
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)
            
            if status == "CRITICAL":
                print(f"🔊 AUDIO TRIGGER: {message} ({obj_name})")

    cv2.imshow("Blind Assist - Danger Tracking", frame)
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()
