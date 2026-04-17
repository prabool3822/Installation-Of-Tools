# Jenkins Installation Commands (Ubuntu + EC2)

## 1. Connect to EC2

ssh -i your-key.pem ubuntu@your-public-ip

---

## 2. Update System

sudo apt update

---

## 3. Install Java

sudo apt install openjdk-17-jdk -y

Check version:
java -version

---

## 4. Add Jenkins Key

curl -fsSL https://pkg.jenkins.io/debian/jenkins.io-2023.key | sudo tee 
/usr/share/keyrings/jenkins-keyring.asc > /dev/null

---

## 5. Add Jenkins Repo

echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] 
https://pkg.jenkins.io/debian binary/ | sudo tee 
/etc/apt/sources.list.d/jenkins.list > /dev/null

---

## 6. Install Jenkins

sudo apt update
sudo apt install jenkins -y

---

## 7. Start Jenkins

sudo systemctl start jenkins
sudo systemctl enable jenkins

---

## 8. Check Status

sudo systemctl status jenkins

---

## 9. Get Admin Password

sudo cat /var/lib/jenkins/secrets/initialAdminPassword

---

## 10. Allow Port (if needed)

sudo ufw allow 8080

---

## 11. View Logs (if error)

sudo journalctl -u jenkins
