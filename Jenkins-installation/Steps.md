# Jenkins Installation Steps (Ubuntu + EC2)

## 1. Launch EC2 Instance

* Go to AWS Console
* Launch Ubuntu instance
* Allow ports:

  * 22 (SSH)
  * 8080 (Jenkins)

---

## 2. Connect to EC2

* Use SSH with your key
* Connect as ubuntu user

---

## 3. Install Java

* Jenkins requires Java to run
* Install OpenJDK 17

---

## 4. Add Jenkins Repository

* Add Jenkins official key
* Add Jenkins repository to system

---

## 5. Install Jenkins

* Update packages
* Install Jenkins using apt

---

## 6. Start Jenkins Service

* Start Jenkins
* Enable it to run on boot

---

## 7. Access Jenkins UI

* Open browser
* Use: http://<EC2-PUBLIC-IP>:8080

---

## 8. Unlock Jenkins

* Get initial admin password from system
* Paste in browser

---

## 9. Setup Jenkins

* Install suggested plugins
* Create admin user

---

## 10. Jenkins Ready

* Dashboard will open
* Ready for CI/CD pipelines
