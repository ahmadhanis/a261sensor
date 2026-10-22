<?php
 declare(strict_types=1);
 header('Cache-Control: no-store');
 $rows = []; $devices = []; $error = null;
 $device = isset($_GET['device']) && is_string($_GET['device']) ? $_GET['device'] : '';
 try {
     if (is_file(__DIR__ . '/data/dht11.sqlite')) {
         $db = new PDO('sqlite:' . __DIR__ . '/data/dht11.sqlite', null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]);
         $db->exec('PRAGMA busy_timeout=5000');
         if ($db->query("SELECT name FROM sqlite_master WHERE type='table' AND name='tbl_dht11'")->fetch()) {
             $devices = $db->query('SELECT DISTINCT device_id FROM tbl_dht11 WHERE device_id IS NOT NULL ORDER BY device_id')->fetchAll(PDO::FETCH_COLUMN);
             $q = $db->prepare('SELECT id, device_id, temperature, humidity, created_at FROM tbl_dht11' . ($device !== '' ? ' WHERE device_id = ?' : '') . ' ORDER BY id DESC LIMIT 50');
             $q->execute($device !== '' ? [$device] : []);
             $rows = $q->fetchAll();
         }
     }
 } catch (Throwable $e) {
     error_log('DHT11 dashboard: ' . $e->getMessage());
     http_response_code(500);
     $error = 'Unable to load readings. Please try again.';
 }
 if (isset($_GET['format']) && $_GET['format'] === 'json') {
     header('Content-Type: application/json; charset=utf-8');
     echo json_encode(['rows' => $rows, 'devices' => $devices, 'error' => $error]);
     exit;
 }
 function h($v): string { return htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8'); }
?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>DHT11 · Environment dashboard</title>
<link rel="stylesheet" href="dashboard.css">
<script src="dashboard.js" defer></script>
</head>
<body>
<main>
<header><div class="brand"><span class="brand-icon" aria-hidden="true">∿</span><span>SENSOR STATION <small>ESP32 / DHT11</small></span></div><span class="pill">Environmental monitoring</span></header>
<section class="heading"><div><p class="eyebrow">YOUR ENVIRONMENT, AT A GLANCE</p><h1>DHT11 dashboard</h1><p class="muted">Temperature and humidity from your connected devices.</p></div><div class="controls"><form method="get"><label for="device">Device</label><select id="device" name="device"><option value="">All devices</option><?php foreach ($devices as $id): ?><option value="<?= h($id) ?>" <?= $id === $device ? 'selected' : '' ?>><?= h($id) ?></option><?php endforeach; ?></select><button type="submit">Apply</button></form><button id="refresh" type="button">↻ Refresh</button></div></section>
<div class="status"><span id="status" role="status"><?= $error ? h($error) : 'Auto-refresh every 10 seconds' ?></span><label><input id="auto" type="checkbox" checked> Auto-refresh</label></div>
<section class="metrics" aria-label="Latest reading"><article class="metric"><p>Latest temperature</p><div><strong id="temperature">—</strong><span> °C</span></div><small id="temp-device">Waiting for data</small></article><article class="metric blue"><p>Latest humidity</p><div><strong id="humidity">—</strong><span> %</span></div><small id="humidity-device">Waiting for data</small></article><article class="metric neutral"><p>Readings shown</p><div><strong id="count"><?= count($rows) ?></strong><span> / 50</span></div><small>Most recently received readings</small></article><article class="metric neutral"><p>Last reading</p><div class="last-time" id="last-time">—</div><small>Malaysia time · UTC+8</small></article></section>
<section class="charts" aria-label="Reading graphs"><article class="panel"><div class="panel-heading"><div><h2>Temperature</h2><p>Degrees Celsius · oldest to newest</p></div><span class="chart-key">°C</span></div><div id="temperature-chart" class="chart"></div></article><article class="panel"><div class="panel-heading"><div><h2>Humidity</h2><p>Relative humidity · oldest to newest</p></div><span class="chart-key blue-text">%</span></div><div id="humidity-chart" class="chart"></div></article></section>
<section class="panel records"><div class="panel-heading"><div><h2>Latest readings</h2><p>Latest 50 records · newest first · Malaysia time (UTC+8)</p></div><span id="record-count" class="pill"><?= count($rows) ?> records</span></div><div class="table-wrap"><table><thead><tr><th scope="col">ID</th><th scope="col">Device</th><th scope="col">Temperature</th><th scope="col">Humidity</th><th scope="col">Received at</th></tr></thead><tbody id="readings"><?php foreach ($rows as $row): ?><tr><td><?= h($row['id']) ?></td><td><?= h($row['device_id'] ?? 'Unknown') ?></td><td><?= h($row['temperature']) ?> °C</td><td><?= h($row['humidity']) ?> %</td><td><?= h((new DateTimeImmutable($row['created_at']))->setTimezone(new DateTimeZone('Asia/Kuala_Lumpur'))->format('d M Y, H:i:s')) ?></td></tr><?php endforeach; ?><?php if (!$rows): ?><tr><td colspan="5" class="empty"><?= $error ? h($error) : 'No readings yet. Send a reading from your ESP32 to get started.' ?></td></tr><?php endif; ?></tbody></table></div></section>
<footer>DHT11 sensor station <span>Temperature in °C · Humidity in %</span></footer>
<noscript><p>Enable JavaScript for graphs and automatic refresh. Use Apply to filter readings.</p></noscript>
</main>
<script id="initial-data" type="application/json"><?= json_encode(['rows' => $rows, 'devices' => $devices, 'error' => $error], JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?></script>
</body></html>
