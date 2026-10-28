.PHONY: help test status version commit tag-patch tag-minor tag-major push release release-minor release-major

# Цвета для вывода
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
NC := \033[0m # No Color

# Получить текущую версию из git tags
CURRENT_VERSION := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
VERSION_PARTS := $(subst ., ,$(subst v,,$(CURRENT_VERSION)))
MAJOR := $(word 1,$(VERSION_PARTS))
MINOR := $(word 2,$(VERSION_PARTS))
PATCH := $(word 3,$(VERSION_PARTS))

# Вычислить следующие версии
NEXT_PATCH := v$(MAJOR).$(MINOR).$(shell echo $$(($(PATCH) + 1)))
NEXT_MINOR := v$(MAJOR).$(shell echo $$(($(MINOR) + 1))).0
NEXT_MAJOR := v$(shell echo $$(($(MAJOR) + 1))).0.0

help: ## Показать эту справку
	@echo "$(BLUE)ZMK Config - Управление версиями и коммитами$(NC)"
	@echo ""
	@echo "$(GREEN)Текущая версия:$(NC) $(CURRENT_VERSION)"
	@echo ""
	@echo "$(YELLOW)Доступные команды:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-18s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Примеры:$(NC)"
	@echo "  make commit MSG=\"Fix bug\"         # Коммит с сообщением"
	@echo "  make release MSG=\"Add feature\"    # Коммит + patch tag + push"
	@echo "  make release-minor MSG=\"New API\"  # Коммит + minor tag + push"
	@echo ""

test: ## Проверить раскладку (слои, комбо, выход из слоёв): нужен pytest
	@python3 -m pytest -q

status: ## Показать git status
	@echo "$(BLUE)Git Status:$(NC)"
	@git status -s
	@echo ""
	@echo "$(BLUE)Текущая версия:$(NC) $(CURRENT_VERSION)"
	@echo "$(BLUE)Последний коммит:$(NC)"
	@git log -1 --oneline

version: ## Показать текущую и следующие версии
	@echo "$(BLUE)Текущая версия:$(NC) $(CURRENT_VERSION)"
	@echo ""
	@echo "$(YELLOW)Следующие версии:$(NC)"
	@echo "  Patch: $(NEXT_PATCH)"
	@echo "  Minor: $(NEXT_MINOR)"
	@echo "  Major: $(NEXT_MAJOR)"

commit: ## Коммит изменений (использование: make commit MSG="commit message")
ifndef MSG
	@echo "$(RED)Ошибка: необходимо указать сообщение коммита$(NC)"
	@echo "Использование: make commit MSG=\"commit message\""
	@exit 1
endif
	@echo "$(BLUE)Коммит изменений...$(NC)"
	@git add -A
	@git commit -m "$(MSG)" -m "Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>" || (echo "$(RED)Нет изменений для коммита$(NC)" && exit 1)
	@echo "$(GREEN)✅ Коммит создан$(NC)"

tag-patch: ## Создать patch тег (v1.2.3 -> v1.2.4)
	@echo "$(BLUE)Создание patch тега: $(CURRENT_VERSION) -> $(NEXT_PATCH)$(NC)"
	@git tag -a $(NEXT_PATCH) -m "Release $(NEXT_PATCH)"
	@echo "$(GREEN)✅ Тег $(NEXT_PATCH) создан$(NC)"

tag-minor: ## Создать minor тег (v1.2.3 -> v1.3.0)
	@echo "$(BLUE)Создание minor тега: $(CURRENT_VERSION) -> $(NEXT_MINOR)$(NC)"
	@git tag -a $(NEXT_MINOR) -m "Release $(NEXT_MINOR)"
	@echo "$(GREEN)✅ Тег $(NEXT_MINOR) создан$(NC)"

tag-major: ## Создать major тег (v1.2.3 -> v2.0.0)
	@echo "$(BLUE)Создание major тега: $(CURRENT_VERSION) -> $(NEXT_MAJOR)$(NC)"
	@git tag -a $(NEXT_MAJOR) -m "Release $(NEXT_MAJOR)"
	@echo "$(GREEN)✅ Тег $(NEXT_MAJOR) создан$(NC)"

push: ## Запушить коммиты и теги
	@echo "$(BLUE)Пуш в origin...$(NC)"
	@git push origin master
	@git push origin --tags
	@echo "$(GREEN)✅ Изменения и теги запушены$(NC)"

release: ## Полный релиз patch версии: commit + tag-patch + push
ifndef MSG
	@echo "$(RED)Ошибка: необходимо указать сообщение коммита$(NC)"
	@echo "Использование: make release MSG=\"commit message\""
	@exit 1
endif
	@echo "$(YELLOW)========================================$(NC)"
	@echo "$(YELLOW)Релиз patch версии: $(NEXT_PATCH)$(NC)"
	@echo "$(YELLOW)========================================$(NC)"
	@$(MAKE) commit MSG="$(MSG)"
	@$(MAKE) tag-patch
	@$(MAKE) push
	@echo ""
	@echo "$(GREEN)🎉 Релиз $(NEXT_PATCH) завершен!$(NC)"
	@echo "$(BLUE)GitHub Actions:$(NC) https://github.com/mshegolev/zmk-config-s/actions"

release-minor: ## Полный релиз minor версии: commit + tag-minor + push
ifndef MSG
	@echo "$(RED)Ошибка: необходимо указать сообщение коммита$(NC)"
	@echo "Использование: make release-minor MSG=\"commit message\""
	@exit 1
endif
	@echo "$(YELLOW)========================================$(NC)"
	@echo "$(YELLOW)Релиз minor версии: $(NEXT_MINOR)$(NC)"
	@echo "$(YELLOW)========================================$(NC)"
	@$(MAKE) commit MSG="$(MSG)"
	@$(MAKE) tag-minor
	@$(MAKE) push
	@echo ""
	@echo "$(GREEN)🎉 Релиз $(NEXT_MINOR) завершен!$(NC)"
	@echo "$(BLUE)GitHub Actions:$(NC) https://github.com/mshegolev/zmk-config-s/actions"

release-major: ## Полный релиз major версии: commit + tag-major + push
ifndef MSG
	@echo "$(RED)Ошибка: необходимо указать сообщение коммита$(NC)"
	@echo "Использование: make release-major MSG=\"commit message\""
	@exit 1
endif
	@echo "$(YELLOW)========================================$(NC)"
	@echo "$(YELLOW)Релиз major версии: $(NEXT_MAJOR)$(NC)"
	@echo "$(YELLOW)========================================$(NC)"
	@$(MAKE) commit MSG="$(MSG)"
	@$(MAKE) tag-major
	@$(MAKE) push
	@echo ""
	@echo "$(GREEN)🎉 Релиз $(NEXT_MAJOR) завершен!$(NC)"
	@echo "$(BLUE)GitHub Actions:$(NC) https://github.com/mshegolev/zmk-config-s/actions"

# Алиасы для удобства
r: release ## Алиас для release
rm: release-minor ## Алиас для release-minor
rM: release-major ## Алиас для release-major
s: status ## Алиас для status
v: version ## Алиас для version
