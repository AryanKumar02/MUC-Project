#include <Arduino.h>
#include <Arduino_LSM9DS1.h>
#include <ArduinoBLE.h>
#include "rotational_model_data.h"  // TFLite model header for rotation (curling) exercise
#include "vertical_model_data.h"
#include "horizontal_model_data.h"

// ---------------- BLE Declarations ----------------
BLEService gymService("19b9d254-3c2a-44b4-95d0-11746426f144");
BLEFloatCharacteristic rotationTotalCharacteristic("ff7f", BLERead | BLENotify);
BLEIntCharacteristic repCountCharacteristic("793d", BLERead | BLENotify);
BLEIntCharacteristic distanceCountCharacteristic("7a2e", BLERead | BLENotify);
BLEIntCharacteristic modeCharacteristic("330d", BLERead | BLEWrite);
BLEIntCharacteristic sessionStatusCharacteristic("a200", BLERead | BLEWrite);
BLEStringCharacteristic motionQualityCharacteristic("00a3", BLERead | BLENotify, 20);

// ---------------- Global Variables for BLE & Sensor ----------------
float cumulativeRotationDegrees = 0.0;
int repCount = 0;         // Each full rep is counted once
int operationMode = 0;    // 0: idle; 1: rotation; 2: vertical; 3: horizontal
int sessionStatus = 0;    // 0: not started; 1: started
unsigned long previousTimeMicros = 0;

// For throttling BLE notifications
unsigned long lastRotationUpdateTime = 0;
unsigned long lastVerticalUpdateTime = 0;
unsigned long lastHorizontalUpdateTime = 0;
const unsigned long BLE_UPDATE_INTERVAL = 50; // ms

// Calibration variables and state (for modes 2 & 3)
bool calibrationDone = false;
bool calibrationInProgress = false;
unsigned long calibrationStartTime = 0;
int calibrationCount = 0;
float calibrationSum = 0.0;
unsigned long nextCalibrationTime = 0;
const unsigned long CALIBRATION_DELAY_MS = 5000;    // Delay before starting calibration (ms)
const unsigned long CALIBRATION_SAMPLE_INTERVAL = 10; // ms between samples
const int CALIBRATION_SAMPLE_COUNT = 100;           // Number of samples to average

// Thresholds and constants
const float gyroscopeNoiseThreshold = 10.0;       // For rotation mode (deg/sec)
const float rotationRepThresholdDegrees = 20.0;     // Threshold angle (deg) for a half rep
const float accelerationNoiseThreshold = 0.05;      // For accelerometer (m/s²)
const float pressingRepThresholdDistance = 0.005;   // Pressing rep threshold (m)
const unsigned long INACTIVITY_MS = 300;            // Inactivity threshold (ms)

// ---------------- Rotation Mode (Mode 1) Variables ----------------
int rotationDirection = 0;
float accumulatedAngleDegrees = 0.0;
float halfRepAngle = 0.0;  // Holds one half rep angle

// ---------------- Vertical Pressing (Mode 2) Variables ----------------
float baselineY = 0.0;
float verticalTotalDistance = 0.0;
float verticalVelocity = 0.0;

// ---------------- Horizontal Pressing (Mode 3) Variables ----------------
float baselineX = 0.0;
float horizontalTotalDistance = 0.0;
float horizontalVelocity = 0.0;

// ---------------- Classification Labels ----------------
const char* rep_quality_labels[] = {"bad", "excellent", "good", "okay", "perfect"};

// ---------------- TFLite Model & Interpreter ----------------
#include <TensorFlowLite.h>
#include "tensorflow/lite/micro/all_ops_resolver.h"
#include "tensorflow/lite/micro/micro_interpreter.h"
#include "tensorflow/lite/schema/schema_generated.h"

constexpr int kTensorArenaSize = 2000;
uint8_t tensor_arena_rotation[kTensorArenaSize];
uint8_t tensor_arena_vertical[kTensorArenaSize];
uint8_t tensor_arena_horizontal[kTensorArenaSize];

tflite::AllOpsResolver resolver_tflite;

// Rotation model globals 
const tflite::Model* model_rotation = nullptr; 
tflite::MicroInterpreter* interpreter_rotation = nullptr; 
TfLiteTensor* input_tensor_rotation = nullptr; 
TfLiteTensor* output_tensor_rotation = nullptr;

// Vertical model globals 
const tflite::Model* model_vertical = nullptr; 
tflite::MicroInterpreter* interpreter_vertical = nullptr; 
TfLiteTensor* input_tensor_vertical = nullptr; 
TfLiteTensor* output_tensor_vertical = nullptr;

// Horizontal model globals 
const tflite::Model* model_horizontal = nullptr; 
tflite::MicroInterpreter* interpreter_horizontal = nullptr; 
TfLiteTensor* input_tensor_horizontal = nullptr; 
TfLiteTensor* output_tensor_horizontal = nullptr;

// ---------------- Model Initialization Functions ---------------- 
void initRotationModel() { 
  model_rotation = tflite::GetModel(rotational_model_data); // from rotational_model_data.h 
  if (model_rotation->version() != TFLITE_SCHEMA_VERSION) { 
    Serial.println("Rotation model schema mismatch!"); 
    while (1); 
  } 
  static tflite::MicroInterpreter static_interpreter(model_rotation, resolver_tflite, tensor_arena_rotation, kTensorArenaSize, nullptr); 
  interpreter_rotation = &static_interpreter; 
  if (interpreter_rotation->AllocateTensors() != kTfLiteOk) { 
    Serial.println("Rotation AllocateTensors() failed"); 
    while (1); 
  } 
  input_tensor_rotation = interpreter_rotation->input(0); 
  output_tensor_rotation = interpreter_rotation->output(0); 
}

void initVerticalModel() { 
  model_vertical = tflite::GetModel(vertical_model_data);  // from vertical_model_data.h 
  if (model_vertical->version() != TFLITE_SCHEMA_VERSION) { 
    Serial.println("Vertical model schema mismatch!"); 
    while (1);
  } 
  static tflite::MicroInterpreter static_interpreter(model_vertical, resolver_tflite, tensor_arena_vertical, kTensorArenaSize, nullptr); 
  interpreter_vertical = &static_interpreter; 
  if (interpreter_vertical->AllocateTensors() != kTfLiteOk) { 
    Serial.println("Vertical AllocateTensors() failed"); 
    while (1); 
  } 
  input_tensor_vertical = interpreter_vertical->input(0); 
  output_tensor_vertical = interpreter_vertical->output(0); 
}

void initHorizontalModel() { 
  model_horizontal = tflite::GetModel(horizontal_model_data); // from horizontal_model_data.h 
  if (model_horizontal->version() != TFLITE_SCHEMA_VERSION) { 
    Serial.println("Horizontal model schema mismatch!"); 
    while (1); 
  } 
  static tflite::MicroInterpreter static_interpreter(model_horizontal, resolver_tflite, tensor_arena_horizontal, kTensorArenaSize, nullptr); 
  interpreter_horizontal = &static_interpreter; 
  if (interpreter_horizontal->AllocateTensors() != kTfLiteOk) { 
    Serial.println("Horizontal AllocateTensors() failed"); 
    while (1); 
  } 
  input_tensor_horizontal = interpreter_horizontal->input(0); 
  output_tensor_horizontal = interpreter_horizontal->output(0); 
}

// ---------------- Reset Function ----------------
void resetSession() {
  cumulativeRotationDegrees = 0;
  repCount = 0;
  rotationDirection = 0;
  accumulatedAngleDegrees = 0.0;
  halfRepAngle = 0.0;
  verticalTotalDistance = 0.0;
  verticalVelocity = 0.0;
  horizontalTotalDistance = 0.0;
  horizontalVelocity = 0.0;
  previousTimeMicros = micros();
  calibrationDone = false;
  calibrationInProgress = false;
  calibrationStartTime = millis();
  calibrationCount = 0;
  calibrationSum = 0.0;
  Serial.println("Session reset: All integration values cleared.");
}

// ---------------- BLE Event Handlers ----------------
void onModeWritten(BLEDevice central, BLECharacteristic characteristic) {
  int newMode = modeCharacteristic.value();
  if (newMode != operationMode) {
    operationMode = newMode;
    resetSession();
    Serial.print("Mode updated to: ");
    Serial.println(operationMode);
    if (operationMode == 1) {
      calibrationDone = true;
    }
  }
}

void onSessionStatusWritten(BLEDevice central, BLECharacteristic characteristic) {
  sessionStatus = sessionStatusCharacteristic.value();
  Serial.print("Session status updated to: ");
  Serial.println(sessionStatus);
  if (sessionStatus == 1) {
    resetSession();
    if (operationMode != 1) {
      calibrationDone = false;
      calibrationInProgress = false;
      calibrationStartTime = millis();
    } else {
      calibrationDone = true;
    }
  }
}

// ---------------- Setup ----------------
void setup() {
  Serial.begin(115200);
  while (!Serial);
  
  if (!IMU.begin()) {
    Serial.println("Failed to initialize IMU!");
    while (1);
  }
  if (!BLE.begin()) {
    Serial.println("BLE initialization failed!");
    while (1);
  }
  
  BLE.setLocalName("Gym_Arduino");
  BLE.setAdvertisedService(gymService);
  gymService.addCharacteristic(rotationTotalCharacteristic);
  gymService.addCharacteristic(repCountCharacteristic);
  gymService.addCharacteristic(distanceCountCharacteristic);
  gymService.addCharacteristic(modeCharacteristic);
  gymService.addCharacteristic(sessionStatusCharacteristic);
  gymService.addCharacteristic(motionQualityCharacteristic);
  BLE.addService(gymService);
  
  // Write initial BLE values.
  rotationTotalCharacteristic.writeValue(cumulativeRotationDegrees);
  repCountCharacteristic.writeValue(repCount);
  distanceCountCharacteristic.writeValue(0);
  modeCharacteristic.writeValue(operationMode);
  sessionStatusCharacteristic.writeValue(sessionStatus);
  motionQualityCharacteristic.writeValue("");
  
  modeCharacteristic.setEventHandler(BLEWritten, onModeWritten);
  sessionStatusCharacteristic.setEventHandler(BLEWritten, onSessionStatusWritten);
  
  BLE.advertise();
  
  initRotationModel();
  initVerticalModel();
  initHorizontalModel();

  previousTimeMicros = micros();
  calibrationStartTime = millis();
  Serial.println("IMU and BLE initialized successfully. Starting rep classification session...");
}

// ---------------- Loop ----------------
void loop() {
  BLEDevice central = BLE.central();
  if (central) {
    Serial.print("Connected to Central: ");
    Serial.println(central.address());
    
    while (central.connected()) {
      // --- Non-blocking Calibration for Vertical (Mode 2) & Horizontal (Mode 3) ---
      if ((operationMode == 2 || operationMode == 3) && sessionStatus == 1 && !calibrationDone) {
        if (!calibrationInProgress && (millis() - calibrationStartTime >= CALIBRATION_DELAY_MS)) {
          calibrationInProgress = true;
          calibrationCount = 0;
          calibrationSum = 0.0;
          nextCalibrationTime = millis();
          Serial.println("Starting calibration... keep device still.");
        }
        if (calibrationInProgress) {
          if (millis() >= nextCalibrationTime) {
            float ax, ay, az;
            if (IMU.accelerationAvailable() && IMU.readAcceleration(ax, ay, az)) {
              if (operationMode == 2) {
                calibrationSum += ay;
              } else if (operationMode == 3) {
                calibrationSum += ax;
              }
              calibrationCount++;
            }
            nextCalibrationTime = millis() + CALIBRATION_SAMPLE_INTERVAL;
          }
          if (calibrationCount >= CALIBRATION_SAMPLE_COUNT) {
            if (operationMode == 2) {
              baselineY = calibrationSum / calibrationCount;
              Serial.print("Calibrated baselineY: ");
              Serial.println(baselineY);
            } else if (operationMode == 3) {
              baselineX = calibrationSum / calibrationCount;
              Serial.print("Calibrated baselineX: ");
              Serial.println(baselineX);
            }
            calibrationDone = true;
            calibrationInProgress = false;
            Serial.println("Calibration complete. Starting exercise.");
          }
          BLE.poll();
          continue; // Wait until calibration is complete
        }
      }
      
      // --- Mode 1: Rotation (Gyroscope & TFLite Classification) ---
      if (operationMode == 1 && sessionStatus == 1) {
        if (IMU.gyroscopeAvailable()) {
          float gx, gy, gz;
          if (IMU.readGyroscope(gx, gy, gz)) {
            unsigned long currentTime = micros();
            float dt = (currentTime - previousTimeMicros) / 1000000.0;
            previousTimeMicros = currentTime;
            float absGz = fabs(gz);
            if (absGz < gyroscopeNoiseThreshold) absGz = 0;
            float deltaDegrees = absGz * dt;
            cumulativeRotationDegrees += deltaDegrees;
            
            if (fabs(gz) >= gyroscopeNoiseThreshold) {
              int readingDirection = (gz > 0) ? 1 : -1;
              if (rotationDirection == 0) {
                rotationDirection = readingDirection;
                accumulatedAngleDegrees = deltaDegrees;
              } else if (readingDirection == rotationDirection) {
                accumulatedAngleDegrees += deltaDegrees;
              } else {
                if (accumulatedAngleDegrees >= rotationRepThresholdDegrees) {
                  if (halfRepAngle == 0.0) {
                    halfRepAngle = accumulatedAngleDegrees;
                  } else {
                    float fullRepDegrees = halfRepAngle + accumulatedAngleDegrees;
                    repCount++;  // full rep detected
                    
                    // Prepare feature vector for TFLite model:
                    input_tensor_rotation->data.f[0] = fullRepDegrees;
                    input_tensor_rotation->data.f[1] = cumulativeRotationDegrees;
                    input_tensor_rotation->data.f[2] = 1.0;
                    if (interpreter_rotation->Invoke() != kTfLiteOk) {
                      Serial.println("Rotation: Invoke failed");
                    } else {
                      float max_score = output_tensor_rotation->data.f[0];
                      int max_index = 0;
                      for (int i = 1; i < 5; i++) {
                        if (output_tensor_rotation->data.f[i] > max_score) {
                          max_score = output_tensor_rotation->data.f[i];
                          max_index = i;
                        }
                      }
                      motionQualityCharacteristic.writeValue(rep_quality_labels[max_index]);
                      repCountCharacteristic.writeValue(repCount);
                      // Call BLE.poll() after heavy processing.
                      Serial.print("Rotation Rep ");
                      Serial.print(repCount);
                      Serial.print(" (");
                      Serial.print(fullRepDegrees);
                      Serial.print("°): Classified as ");
                      Serial.println(rep_quality_labels[max_index]);
                      delay(50);
                    }
                    halfRepAngle = 0.0;
                  }
                }
                rotationDirection = readingDirection;
                accumulatedAngleDegrees = deltaDegrees;
              }
            }
            // Throttle BLE update for rotation total.
            if (millis() - lastRotationUpdateTime >= BLE_UPDATE_INTERVAL) {
              rotationTotalCharacteristic.writeValue(cumulativeRotationDegrees);
              lastRotationUpdateTime = millis();
              Serial.print("Total rotation (degrees): ");
              Serial.println(cumulativeRotationDegrees);
              delay(50);
            }
          }
        }
      }
      
      // --- Mode 2: Vertical Pressing (Y-axis, Threshold Classification) ---
      if (operationMode == 2 && sessionStatus == 1) {
        if (IMU.accelerationAvailable()) {
          float ax, ay, az;
          if (IMU.readAcceleration(ax, ay, az)) {
            float rawAccel = ay;
            static float dynamicBias = baselineY;
            const float biasAlpha = 0.01;
            if (fabs(rawAccel - dynamicBias) < 0.3)
              dynamicBias = (1 - biasAlpha) * dynamicBias + biasAlpha * rawAccel;
            float calibratedAccel = rawAccel - dynamicBias;
            if (fabs(calibratedAccel) < accelerationNoiseThreshold) {
              calibratedAccel = 0;
              verticalVelocity = 0;
            }
            unsigned long currentTime = micros();
            float dt = (currentTime - previousTimeMicros) / 1000000.0;
            previousTimeMicros = currentTime;
            float velocity = verticalVelocity + calibratedAccel * dt;
            float deltaDistance = verticalVelocity * dt + 0.5f * calibratedAccel * dt * dt;
            verticalVelocity = velocity;
            verticalTotalDistance += fabs(deltaDistance);
            static float currentDisp = 0.0f;
            static float maxDisp = 0.0f;
            static float minDisp = 0.0f;
            static unsigned long lastMotionTime = millis();
            currentDisp += deltaDistance;
            if (fabs(calibratedAccel) >= accelerationNoiseThreshold) {
              lastMotionTime = millis();
              if (currentDisp > maxDisp) maxDisp = currentDisp;
              if (currentDisp < minDisp) minDisp = currentDisp;
            } else {
              if (millis() - lastMotionTime > INACTIVITY_MS) {
                float repDistance = maxDisp - minDisp;
                if (repDistance >= pressingRepThresholdDistance) {
                  repCount++;
                  float repDistance_cm = repDistance * 100.0;
                  input_tensor_vertical->data.f[0] = repDistance_cm;
                  if (interpreter_vertical->Invoke() != kTfLiteOk) {
                    Serial.println("Vertical: Invoke failed");
                  } else {
                    float max_score = output_tensor_vertical->data.f[0];
                    int max_index = 0;
                    for (int i = 1; i < 5; i++) {
                      if (output_tensor_vertical->data.f[i] > max_score) {
                        max_score = output_tensor_vertical->data.f[i];
                        max_index = i;
                      }  
                    }  
                    repCountCharacteristic.writeValue(repCount);
                    motionQualityCharacteristic.writeValue(rep_quality_labels[max_index]);
                    BLE.poll();
                    Serial.print("Vertical Rep ");
                    Serial.print(repCount);
                    Serial.print(" (");
                    Serial.print(repDistance * 100.0, 4);
                    Serial.print(" cm): Classified as ");
                    Serial.println(rep_quality_labels[max_index]);
                  }
                }
                currentDisp = 0.0f;
                maxDisp = 0.0f;
                minDisp = 0.0f;
              }
            }
            // Throttle vertical distance update.
            if (millis() - lastVerticalUpdateTime >= BLE_UPDATE_INTERVAL) {
              distanceCountCharacteristic.writeValue((int)(verticalTotalDistance * 100));
              lastVerticalUpdateTime = millis();
              Serial.print("Vertical Total Distance (cm): ");
              Serial.println(verticalTotalDistance * 100, 4);
            }
          }
        }
      }
      
      // --- Mode 3: Horizontal Pressing (X-axis, Threshold Classification) ---
      if (operationMode == 3 && sessionStatus == 1) {
        if (IMU.accelerationAvailable()) {
          float ax, ay, az;
          if (IMU.readAcceleration(ax, ay, az)) {
            float rawAccel = ax;
            static float dynamicBias = baselineX;
            const float biasAlpha = 0.01;
            if (fabs(rawAccel - dynamicBias) < 0.3)
              dynamicBias = (1 - biasAlpha) * dynamicBias + biasAlpha * rawAccel;
            float calibratedAccel = rawAccel - dynamicBias;
            if (fabs(calibratedAccel) < accelerationNoiseThreshold) {
              calibratedAccel = 0;
              horizontalVelocity = 0;
            }
            unsigned long currentTime = micros();
            float dt = (currentTime - previousTimeMicros) / 1000000.0;
            previousTimeMicros = currentTime;
            float velocity = horizontalVelocity + calibratedAccel * dt;
            float deltaDistance = horizontalVelocity * dt + 0.5f * calibratedAccel * dt * dt;
            horizontalVelocity = velocity;
            horizontalTotalDistance += fabs(deltaDistance);
            static float currentDisp = 0.0f;
            static float maxDisp = 0.0f;
            static float minDisp = 0.0f;
            static unsigned long lastMotionTime = millis();
            currentDisp += deltaDistance;
            if (fabs(calibratedAccel) >= accelerationNoiseThreshold) {
              lastMotionTime = millis();
              if (currentDisp > maxDisp) maxDisp = currentDisp;
              if (currentDisp < minDisp) minDisp = currentDisp;
            } else {
              if (millis() - lastMotionTime > INACTIVITY_MS) {
                float repDistance = maxDisp - minDisp;
                if (repDistance >= pressingRepThresholdDistance) {
                  repCount++;
                  float repDistance_cm = repDistance * 100.0;
                  input_tensor_horizontal->data.f[0] = repDistance_cm;
                  if (interpreter_horizontal->Invoke() != kTfLiteOk) {
                    Serial.println("Horizontal: Invoke failed");
                  } else {
                    float max_score = output_tensor_horizontal->data.f[0];
                    int max_index = 0;
                    for (int i = 1; i < 5; i++) {
                      if (output_tensor_horizontal->data.f[i] > max_score) {
                        max_score = output_tensor_horizontal->data.f[i];
                        max_index = i;
                      }
                    }
                    repCountCharacteristic.writeValue(repCount);
                    motionQualityCharacteristic.writeValue(rep_quality_labels[max_index]);
                    BLE.poll();
                    Serial.print("Horizontal Rep ");
                    Serial.print(repCount);
                    Serial.print(" (");
                    Serial.print(repDistance * 100.0, 4);
                    Serial.print(" cm): Classified as ");
                    Serial.println(rep_quality_labels[max_index]);
                  }
                }
                currentDisp = 0.0f;
                maxDisp = 0.0f;
                minDisp = 0.0f;
              }
            }
            // Throttle horizontal distance update.
            if (millis() - lastHorizontalUpdateTime >= BLE_UPDATE_INTERVAL) {
              distanceCountCharacteristic.writeValue((int)(horizontalTotalDistance * 100));
              lastHorizontalUpdateTime = millis();
              Serial.print("Horizontal Total Distance (cm): ");
              Serial.println(horizontalTotalDistance * 100, 4);
            }
          }
        }
      }
      
      // Poll BLE events very frequently.
      BLE.poll();
      // Use a very short delay (if any) to yield CPU without blocking BLE events.
      delay(50);
    }
    Serial.print("Disconnected from central: ");
    Serial.println(central.address());
  }
}
