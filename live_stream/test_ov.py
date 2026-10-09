import urllib.request
url = "https://raw.githubusercontent.com/ComputerNerd/ov7670-no-ram-arduino-uno/master/ov7670.c"
try:
    response = urllib.request.urlopen(url)
    content = response.read().decode("utf-8")
    for line in content.split("\n"):
        if "0x4f" in line.lower() or "0x56" in line.lower() or "0x58" in line.lower() or "mtx" in line.lower():
            print(line.strip())
except Exception as e:
    pass
