<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');

function respond(int $status, array $body): never
{
    http_response_code($status);
    echo json_encode($body, JSON_UNESCAPED_SLASHES);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    respond(405, ['success' => false, 'error' => 'Use POST with device_id, temperature and humidity.']);
}

$type = strtolower(trim(explode(';', $_SERVER['CONTENT_TYPE'] ?? '')[0]));
if ($type === 'application/json') {
    try {
        $data = json_decode(file_get_contents('php://input'), true, 512, JSON_THROW_ON_ERROR);
    } catch (JsonException $e) {
        respond(400, ['success' => false, 'error' => 'Invalid JSON.']);
    }
    if (!is_array($data)) {
        respond(400, ['success' => false, 'error' => 'Send a JSON object with device_id, temperature and humidity.']);
    }
} elseif (in_array($type, ['application/x-www-form-urlencoded', 'multipart/form-data'], true)) {
    $data = $_POST;
} else {
    respond(415, ['success' => false, 'error' => 'Use application/json or form data.']);
}

$deviceId = $data['device_id'] ?? null;
if (!is_string($deviceId) || !preg_match('/\A[A-Za-z0-9_-]{1,64}\z/', $deviceId)) {
    respond(400, ['success' => false, 'error' => 'device_id must contain 1-64 letters, numbers, underscores or hyphens.']);
}

foreach (['temperature', 'humidity'] as $field) {
    if (!isset($data[$field]) || !is_numeric($data[$field]) || !is_finite((float) $data[$field])) {
        respond(400, ['success' => false, 'error' => "$field must be a finite number."]);
    }
}
$temperature = (float) $data['temperature'];
$humidity = (float) $data['humidity'];
if ($humidity < 0 || $humidity > 100) {
    respond(400, ['success' => false, 'error' => 'humidity must be between 0 and 100.']);
}

try {
    $db = new PDO('sqlite:' . __DIR__ . '/data/dht11.sqlite', null, null, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    ]);
    $db->exec('PRAGMA busy_timeout = 5000');
    $db->exec('CREATE TABLE IF NOT EXISTS tbl_dht11 (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        temperature REAL NOT NULL,
        humidity REAL NOT NULL CHECK (humidity BETWEEN 0 AND 100),
        created_at TEXT NOT NULL
    )');
    $createdAt = gmdate('Y-m-d\TH:i:s\Z');
    $statement = $db->prepare('INSERT INTO tbl_dht11 (device_id, temperature, humidity, created_at) VALUES (?, ?, ?, ?)');
    $statement->execute([$deviceId, $temperature, $humidity, $createdAt]);
    respond(201, [
        'success' => true,
        'id' => (int) $db->lastInsertId(),
        'device_id' => $deviceId,
        'temperature' => $temperature,
        'humidity' => $humidity,
        'created_at' => $createdAt,
    ]);
} catch (Throwable $e) {
    error_log('DHT11 insert failed: ' . $e->getMessage());
    respond(500, ['success' => false, 'error' => 'Unable to store reading.']);
}
