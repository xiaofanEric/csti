<?php
if (session_status() !== PHP_SESSION_ACTIVE) {
    session_start();
}

$message = '';
$loggedInUser = $_SESSION['logged_in_user'] ?? '';
$pullOutputLines = [];
$showPullModal = false;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? 'login';

    if ($action === 'logout') {
        $_SESSION = [];
        if (ini_get('session.use_cookies')) {
            $params = session_get_cookie_params();
            setcookie(session_name(), '', time() - 42000, $params['path'], $params['domain'], $params['secure'], $params['httponly']);
        }
        session_destroy();
        $loggedInUser = '';
    }

    if ($action === 'login') {
        $username = trim($_POST['username'] ?? '');
        $password = $_POST['password'] ?? '';

        $jsonPath = __DIR__ . '/password.json';
        $jsonData = @file_get_contents($jsonPath);
        $users = json_decode($jsonData ?: '{}', true);

        if (!is_array($users)) {
            $message = '用户数据异常';
        } elseif (!array_key_exists($username, $users)) {
            $message = '用户名或密码错误';
        } elseif (!password_verify($password, $users[$username])) {
            $message = '用户名或密码错误';
        } else {
            $_SESSION['logged_in_user'] = $username;
            $loggedInUser = $username;
        }
    }

    if ($action === 'pull') {
        if ($loggedInUser === '') {
            $message = '请先登录';
        } else {
            $repoDir = realpath(__DIR__ . '/..');
            if ($repoDir === false) {
                $pullOutputLines = ['仓库目录不存在'];
            } else {
                $cmd = 'cd ' . escapeshellarg($repoDir) . ' && git pull 2>&1';
                exec($cmd, $pullOutputLines, $pullExitCode);
                if (empty($pullOutputLines)) {
                    $pullOutputLines[] = '没有输出';
                }
                $pullOutputLines[] = 'exit code: ' . $pullExitCode;
            }
            $showPullModal = true;
        }
    }
}
?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Admin Login</title>
    <style>
        body {
            font-family: sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            margin: 0;
            background: #f5f7fb;
        }
        .card {
            width: 320px;
            background: #fff;
            border-radius: 12px;
            box-shadow: 0 10px 30px rgba(0, 0, 0, 0.1);
            padding: 24px;
        }
        h1 {
            font-size: 20px;
            margin: 0 0 16px;
            text-align: center;
        }
        label {
            display: block;
            font-size: 14px;
            margin: 10px 0 6px;
        }
        input {
            width: 100%;
            box-sizing: border-box;
            padding: 10px;
            border: 1px solid #d9dfeb;
            border-radius: 8px;
            outline: none;
        }
        input:focus {
            border-color: #4068f0;
        }
        button {
            margin-top: 14px;
            width: 100%;
            padding: 10px;
            border: 0;
            border-radius: 8px;
            background: #4068f0;
            color: #fff;
            font-weight: 600;
            cursor: pointer;
        }
        .btn-secondary {
            background: #2563eb;
        }
        .msg {
            margin-top: 12px;
            font-size: 14px;
            color: #d93025;
            min-height: 20px;
        }
        .ok {
            color: #188038;
        }
        .hello-line {
            display: flex;
            align-items: center;
            gap: 4px;
        }
        .inline-form {
            display: inline;
            margin: 0;
        }
        .link-btn {
            width: auto;
            margin: 0;
            padding: 0;
            border: 0;
            background: transparent;
            color: #188038;
            font-size: 14px;
            font-weight: 400;
            text-decoration: underline;
            cursor: pointer;
        }
        .modal {
            position: fixed;
            inset: 0;
            display: none;
            align-items: center;
            justify-content: center;
            background: rgba(0, 0, 0, 0.55);
            padding: 16px;
            box-sizing: border-box;
        }
        .modal.show {
            display: flex;
        }
        .modal-content {
            width: min(760px, 100%);
            max-height: 80vh;
            overflow: auto;
            background: #101826;
            color: #dbeafe;
            border-radius: 12px;
            padding: 14px;
            box-shadow: 0 10px 30px rgba(0, 0, 0, 0.35);
        }
        .modal-title {
            margin: 0 0 10px;
            font-size: 16px;
            color: #eff6ff;
        }
        .line {
            font-family: monospace;
            font-size: 13px;
            white-space: pre-wrap;
            word-break: break-word;
            padding: 2px 0;
            border-bottom: 1px solid rgba(255, 255, 255, 0.08);
        }
        .line:last-child {
            border-bottom: 0;
        }
        .close-btn {
            margin-top: 12px;
            background: #334155;
        }
    </style>
</head>
<body>
    <div class="card">
        <h1>管理员登录</h1>

        <?php if ($loggedInUser !== ''): ?>
            <div class="msg ok hello-line">
                <span><?php echo 'Hello, ' . htmlspecialchars($loggedInUser, ENT_QUOTES, 'UTF-8'); ?></span>
                <form class="inline-form" method="post" action="">
                    <input type="hidden" name="action" value="logout">
                    <button class="link-btn" type="submit">(注销)</button>
                </form>
            </div>
            <form method="post" action="">
                <input type="hidden" name="action" value="pull">
                <button class="btn-secondary" type="submit">拉取最新版</button>
            </form>
        <?php else: ?>
            <form method="post" action="">
                <input type="hidden" name="action" value="login">
                <label for="username">用户名</label>
                <input id="username" name="username" type="text" required>

                <label for="password">密码</label>
                <input id="password" name="password" type="password" required>

                <button type="submit">登录</button>
            </form>
            <div class="msg"><?php echo htmlspecialchars($message, ENT_QUOTES, 'UTF-8'); ?></div>
        <?php endif; ?>

        <?php if ($loggedInUser !== '' && $message !== ''): ?>
            <div class="msg"><?php echo htmlspecialchars($message, ENT_QUOTES, 'UTF-8'); ?></div>
        <?php endif; ?>
    </div>

    <div id="pullModal" class="modal <?php echo $showPullModal ? 'show' : ''; ?>">
        <div class="modal-content">
            <h2 class="modal-title">git pull 输出</h2>
            <?php foreach ($pullOutputLines as $line): ?>
                <div class="line"><?php echo htmlspecialchars($line, ENT_QUOTES, 'UTF-8'); ?></div>
            <?php endforeach; ?>
            <button class="close-btn" type="button" onclick="closeModal()">关闭</button>
        </div>
    </div>

    <script>
        function closeModal() {
            var modal = document.getElementById('pullModal');
            if (modal) {
                modal.classList.remove('show');
            }
        }

        document.addEventListener('click', function (event) {
            var modal = document.getElementById('pullModal');
            if (modal && modal.classList.contains('show') && event.target === modal) {
                closeModal();
            }
        });
    </script>
</body>
</html>
