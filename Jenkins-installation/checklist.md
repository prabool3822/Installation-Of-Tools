# Jenkins Production Checklist (EC2)

## 🔐 Security
- Allow SSH (22) → your IP only  
- Allow Jenkins port (8080/8081) → your IP only  
- Disable anonymous access  
- Use strong admin credentials  
- Keep CSRF protection enabled  

## 🌐 HTTPS & Domain
- Use domain + HTTPS  
- Setup reverse proxy with Nginx  
- Use SSL via Let’s Encrypt  

## ⚙️ System Setup
- Set Jenkins URL  
- Set timezone  
- Keep executors = 1 (initially)  

## 🔌 Plugins
Install only required plugins:
- Git  
- Pipeline  
- GitHub  
- Docker  

Avoid unnecessary plugins  

## 🏗️ Architecture
- Don’t run builds on controller  
- Use agents (EC2 / Docker)  

## 💾 Backup
- Backup directory:
/var/lib/jenkins

- Include:
- jobs/  
- plugins/  
- config.xml  

## 📊 Monitoring
- Check status:
```bash
systemctl status jenkins
View logs: journalctl -u jenkins
