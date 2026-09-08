# ADR-001: Canary 90/10 для deployment нової моделі

Статус: Accepted  
Авторка: Viktoriia_Kratser

## Контекст

Offline accuracy не гарантує production-поведінку. Потрібно показати нову
модель на реальному трафіку, обмежити blast radius і мати прозорий rollback.

## Рішення

Використовувати два Deployment/Service та NGINX Ingress canary weight 10%.
Stable отримує решту трафіку. Версії model/image/checksum зберігаються в Git;
ArgoCD застосовує й self-heal-ить стан.

## Чому не Blue-Green

Blue-Green простіший для миттєвого перемикання, але до switch не дає реального
порівняння двох моделей на частині production traffic і потребує двох повних
копій. Canary краще демонструє контроль ризику для model rollout.

## Чому не A/B

A/B доречний для бізнес-експерименту зі стабільним поділом користувачів. У
цьому проєкті мета - технічна безпека rollout, а не причинний аналіз поведінки.

## Наслідки і trade-offs

- Плюс: лише близько 10% запитів бачать потенційно погану версію.
- Плюс: weight змінюється reviewable Git commit-ом.
- Мінус: потрібні дві копії застосунку і ingress controller.
- Мінус: 90/10 є статистичним; маленька вибірка може відхилятися.
- Мінус: stateful session routing не реалізовано, бо inference stateless.

За більшого часу додали б automated analysis gate (Argo Rollouts), SLO-based
pause/rollback та shadow traffic перед першими 10%.
