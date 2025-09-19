import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Badge } from '@/components/ui/badge';

interface ModelSelectorProps {
    pureElo: number;
    injuryElo: number;
    currentModel: number;
    selectedModel: number;
    onModelChange: (model: number) => void;
}

export const ModelSelector = ({ pureElo, injuryElo, selectedModel, currentModel, onModelChange }: ModelSelectorProps) => {


    return (
        <div className="flex items-center gap-3">
            <div className="flex items-center gap-2">
                <span className="text-sm font-medium text-muted-foreground">Model:</span>
                <Select
                    value={selectedModel.toString()}
                    onValueChange={(value) => onModelChange(parseInt(value))}
                >
                    <SelectTrigger className="w-20 bg-gradient-card shadow-card">
                        <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                        placeholder for Models
                    </SelectContent>
                </Select>
            </div>
        </div>
    );
};