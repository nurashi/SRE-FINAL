package service

import (
	"context"
	"log"

	"github.com/nurashi/sre-final/domain"
	"github.com/nurashi/sre-final/repository"
)

type TaskService struct {
	repo repository.TaskRepository
}

func NewTaskService(repo repository.TaskRepository) *TaskService {
	return &TaskService{repo: repo}
}

func (s *TaskService) Create(ctx context.Context, req domain.CreateTaskRequest) (domain.Task, error) {
	task, err := s.repo.Create(ctx, req)
	if err != nil {
		log.Printf("Error creating task: %v", err)
		return domain.Task{}, err
	}
	log.Printf("Task created: id=%d title=%s", task.ID, task.Title)
	return task, nil
}

func (s *TaskService) GetAll(ctx context.Context) ([]domain.Task, error) {
	tasks, err := s.repo.GetAll(ctx)
	if err != nil {
		log.Printf("Error getting all tasks: %v", err)
		return nil, err
	}
	return tasks, nil
}

func (s *TaskService) GetByID(ctx context.Context, id int64) (domain.Task, error) {
	task, err := s.repo.GetByID(ctx, id)
	if err != nil {
		log.Printf("Error getting task %d: %v", id, err)
		return domain.Task{}, err
	}
	return task, nil
}

func (s *TaskService) Update(ctx context.Context, id int64, req domain.UpdateTaskRequest) (domain.Task, error) {
	task, err := s.repo.Update(ctx, id, req)
	if err != nil {
		log.Printf("Error updating task %d: %v", id, err)
		return domain.Task{}, err
	}
	log.Printf("Task updated: id=%d", id)
	return task, nil
}

func (s *TaskService) Delete(ctx context.Context, id int64) error {
	if err := s.repo.Delete(ctx, id); err != nil {
		log.Printf("Error deleting task %d: %v", id, err)
		return err
	}
	log.Printf("Task deleted: id=%d", id)
	return nil
}

func (s *TaskService) Health(ctx context.Context) error {
	return s.repo.Health(ctx)
}
