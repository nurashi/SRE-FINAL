package repository

import (
	"context"
	"sync"
	"sync/atomic"
	"time"

	"github.com/nurashi/sre-final/domain"
)

type TaskRepository interface {
	Create(ctx context.Context, task domain.CreateTaskRequest) (domain.Task, error)
	GetAll(ctx context.Context) ([]domain.Task, error)
	GetByID(ctx context.Context, id int64) (domain.Task, error)
	Update(ctx context.Context, id int64, req domain.UpdateTaskRequest) (domain.Task, error)
	Delete(ctx context.Context, id int64) error
	Health(ctx context.Context) error
}

type memoryRepository struct {
	mu     sync.RWMutex
	tasks  map[int64]domain.Task
	nextID atomic.Int64
}

func NewTaskRepository() TaskRepository {
	repo := &memoryRepository{
		tasks: make(map[int64]domain.Task),
	}
	repo.nextID.Store(1)
	return repo
}

func (r *memoryRepository) Create(ctx context.Context, req domain.CreateTaskRequest) (domain.Task, error) {
	now := time.Now().UTC()
	id := r.nextID.Add(1) - 1
	task := domain.Task{
		ID:          id,
		Title:       req.Title,
		Description: req.Description,
		Completed:   false,
		CreatedAt:   now,
		UpdatedAt:   now,
	}

	r.mu.Lock()
	r.tasks[task.ID] = task
	r.mu.Unlock()

	return task, nil
}

func (r *memoryRepository) GetAll(ctx context.Context) ([]domain.Task, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	tasks := make([]domain.Task, 0, len(r.tasks))
	for _, t := range r.tasks {
		tasks = append(tasks, t)
	}
	return tasks, nil
}

func (r *memoryRepository) GetByID(ctx context.Context, id int64) (domain.Task, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	task, ok := r.tasks[id]
	if !ok {
		return domain.Task{}, ErrNotFound
	}
	return task, nil
}

func (r *memoryRepository) Update(ctx context.Context, id int64, req domain.UpdateTaskRequest) (domain.Task, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	task, ok := r.tasks[id]
	if !ok {
		return domain.Task{}, ErrNotFound
	}

	if req.Title != "" {
		task.Title = req.Title
	}
	if req.Description != "" {
		task.Description = req.Description
	}
	if req.Completed != nil {
		task.Completed = *req.Completed
	}
	task.UpdatedAt = time.Now().UTC()

	r.tasks[id] = task
	return task, nil
}

func (r *memoryRepository) Delete(ctx context.Context, id int64) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	if _, ok := r.tasks[id]; !ok {
		return ErrNotFound
	}
	delete(r.tasks, id)
	return nil
}

func (r *memoryRepository) Health(ctx context.Context) error {
	return nil
}

var ErrNotFound = domain.ErrNotFound
