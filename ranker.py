import pydicom
import cv2
import numpy as np
import os
import pandas as pd
from pathlib import Path
import shutil
from scipy import ndimage
from skimage import filters, measure, feature
from sklearn.decomposition import PCA
import matplotlib.pyplot as plt

class FetalBrainOrientationDetector:
    def __init__(self):
        # Anatomical feature templates for different orientations
        self.orientation_features = {
            'axial': {
                'aspect_ratio_range': (0.8, 1.3),  # More circular
                'symmetry_axis': 'horizontal',
                'expected_structures': ['lateral_ventricles', 'hemispheres']
            },
            'sagittal': {
                'aspect_ratio_range': (0.6, 1.0),  # More elongated
                'symmetry_axis': 'vertical', 
                'expected_structures': ['midline', 'brainstem', 'cerebellum']
            },
            'coronal': {
                'aspect_ratio_range': (0.9, 1.4),
                'symmetry_axis': 'vertical',
                'expected_structures': ['bilateral_symmetry', 'ventricles']
            }
        }
    
    def detect_brain_region(self, image_array):
        """
        Detect the fetal brain region in the maternal MRI
        """
        # Normalize image
        img_norm = cv2.normalize(image_array, None, 0, 255, cv2.NORM_MINMAX, dtype=cv2.CV_8U)
        
        # Apply Gaussian blur to reduce noise
        img_blur = cv2.GaussianBlur(img_norm, (5, 5), 1.0)
        
        # Use Otsu's thresholding to segment brain tissue
        _, binary = cv2.threshold(img_blur, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        
        # Find connected components
        contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        if not contours:
            return None, None
        
        # Find the largest connected component (likely the brain)
        largest_contour = max(contours, key=cv2.contourArea)
        
        # Create mask for brain region
        mask = np.zeros_like(binary)
        cv2.fillPoly(mask, [largest_contour], 255)
        
        # Get bounding box
        x, y, w, h = cv2.boundingRect(largest_contour)
        
        # Extract brain region
        brain_region = img_norm[y:y+h, x:x+w]
        brain_mask = mask[y:y+h, x:x+w]
        
        return brain_region, brain_mask
    
    def analyze_symmetry(self, brain_region, brain_mask):
        """
        Analyze symmetry patterns to determine orientation
        """
        if brain_region is None:
            return {}
        
        h, w = brain_region.shape
        
        # Horizontal symmetry (left-right)
        left_half = brain_region[:, :w//2]
        right_half = brain_region[:, w//2:]
        right_half_flipped = np.fliplr(right_half)
        
        # Resize to match if needed
        min_width = min(left_half.shape[1], right_half_flipped.shape[1])
        left_half = left_half[:, :min_width]
        right_half_flipped = right_half_flipped[:, :min_width]
        
        horizontal_symmetry = np.corrcoef(left_half.flatten(), right_half_flipped.flatten())[0, 1]
        
        # Vertical symmetry (top-bottom)
        top_half = brain_region[:h//2, :]
        bottom_half = brain_region[h//2:, :]
        bottom_half_flipped = np.flipud(bottom_half)
        
        min_height = min(top_half.shape[0], bottom_half_flipped.shape[0])
        top_half = top_half[:min_height, :]
        bottom_half_flipped = bottom_half_flipped[:min_height, :]
        
        vertical_symmetry = np.corrcoef(top_half.flatten(), bottom_half_flipped.flatten())[0, 1]
        
        return {
            'horizontal_symmetry': horizontal_symmetry if not np.isnan(horizontal_symmetry) else 0,
            'vertical_symmetry': vertical_symmetry if not np.isnan(vertical_symmetry) else 0
        }
    
    def detect_anatomical_features(self, brain_region, brain_mask):
        """
        Detect specific anatomical features for orientation determination
        """
        if brain_region is None:
            return {}
        
        features = {}
        
        # Aspect ratio
        h, w = brain_region.shape
        aspect_ratio = w / h
        features['aspect_ratio'] = aspect_ratio
        
        # Edge analysis
        edges = cv2.Canny(brain_region, 50, 150)
        
        # Detect lines using Hough transform
        lines = cv2.HoughLines(edges, 1, np.pi / 180, threshold=50)
        
        if lines is not None:
            # Analyze line orientations
            angles = []
            for line in lines:
                rho, theta = line[0]
                angle = theta * 180 / np.pi
                angles.append(angle)
            
            features['dominant_line_angle'] = np.median(angles) if angles else 0
            features['line_count'] = len(angles)
        else:
            features['dominant_line_angle'] = 0
            features['line_count'] = 0
        
        # Intensity distribution analysis
        features['intensity_std'] = np.std(brain_region)
        features['intensity_skewness'] = self.calculate_skewness(brain_region)
        
        return features
    
    def calculate_skewness(self, image):
        """Calculate skewness of intensity distribution"""
        flat = image.flatten()
        mean = np.mean(flat)
        std = np.std(flat)
        if std == 0:
            return 0
        return np.mean(((flat - mean) / std) ** 3)
    
    def determine_fetal_orientation(self, image_array):
        """
        Determine the fetal brain orientation within maternal MRI
        """
        # Extract brain region
        brain_region, brain_mask = self.detect_brain_region(image_array)
        
        if brain_region is None:
            return 'unknown', 0.0, {}
        
        # Analyze features
        symmetry_features = self.analyze_symmetry(brain_region, brain_mask)
        anatomical_features = self.detect_anatomical_features(brain_region, brain_mask)
        
        # Combine all features
        all_features = {**symmetry_features, **anatomical_features}
        
        # Orientation scoring
        scores = {
            'axial': 0.0,
            'sagittal': 0.0,
            'coronal': 0.0
        }
        
        # Axial scoring (typically shows bilateral symmetry)
        if all_features.get('horizontal_symmetry', 0) > 0.5:
            scores['axial'] += 3.0
        if 0.8 <= all_features.get('aspect_ratio', 0) <= 1.3:
            scores['axial'] += 2.0
        if all_features.get('intensity_std', 0) > 20:  # Good contrast
            scores['axial'] += 1.0
        
        # Sagittal scoring (shows midline structures)
        if all_features.get('vertical_symmetry', 0) < 0.3:  # Less vertical symmetry
            scores['sagittal'] += 2.0
        if 0.6 <= all_features.get('aspect_ratio', 0) <= 1.0:
            scores['sagittal'] += 2.0
        if abs(all_features.get('dominant_line_angle', 90) - 90) < 20:  # Vertical structures
            scores['sagittal'] += 2.0
        
        # Coronal scoring 
        if all_features.get('vertical_symmetry', 0) > 0.4:
            scores['coronal'] += 2.0
        if 0.9 <= all_features.get('aspect_ratio', 0) <= 1.4:
            scores['coronal'] += 1.5
        if all_features.get('horizontal_symmetry', 0) > 0.3:
            scores['coronal'] += 1.5
        
        # Determine best orientation
        best_orientation = max(scores, key=scores.get)
        best_score = scores[best_orientation]
        confidence = min(best_score / 5.0, 1.0)  # Normalize to 0-1
        
        return best_orientation, confidence, all_features

class FetalBrainQualityAssessor:
    def __init__(self):
        self.orientation_detector = FetalBrainOrientationDetector()
        
        # Orientation-specific quality thresholds
        self.quality_thresholds = {
            'axial': {
                'excellent': 75,
                'good': 60,
                'fair': 40,
                'blur_weight': 0.3,
                'contrast_weight': 0.25,
                'symmetry_weight': 0.2
            },
            'sagittal': {
                'excellent': 70,  # Slightly lower due to complexity
                'good': 55,
                'fair': 35,
                'blur_weight': 0.35,
                'contrast_weight': 0.2,
                'symmetry_weight': 0.15
            },
            'coronal': {
                'excellent': 72,
                'good': 58,
                'fair': 38,
                'blur_weight': 0.25,
                'contrast_weight': 0.3,
                'symmetry_weight': 0.25
            },
            'unknown': {
                'excellent': 65,
                'good': 50,
                'fair': 30,
                'blur_weight': 0.4,
                'contrast_weight': 0.3,
                'symmetry_weight': 0.1
            }
        }
    
    def calculate_orientation_specific_quality(self, image_array, orientation, orientation_features):
        """
        Calculate quality metrics specific to the detected orientation
        """
        # Normalize to 8-bit
        if image_array.dtype != np.uint8:
            img_normalized = cv2.normalize(image_array, None, 0, 255, cv2.NORM_MINMAX, dtype=cv2.CV_8U)
        else:
            img_normalized = image_array.copy()
        
        # Apply mild denoising
        img_denoised = cv2.GaussianBlur(img_normalized, (3, 3), 0.5)
        
        metrics = {}
        
        # Basic quality metrics
        laplacian = cv2.Laplacian(img_denoised, cv2.CV_64F)
        metrics['sharpness_score'] = laplacian.var()
        
        metrics['contrast'] = np.std(img_normalized)
        
        # SNR calculation
        signal = np.mean(img_normalized)
        noise_regions = self.get_noise_regions(img_normalized)
        noise_std = np.std(noise_regions) if len(noise_regions) > 0 else 1
        metrics['snr'] = signal / (noise_std + 1e-10)
        
        # Orientation-specific metrics
        if orientation == 'axial':
            # For axial: emphasize bilateral symmetry and circular features
            metrics['bilateral_symmetry'] = orientation_features.get('horizontal_symmetry', 0)
            metrics['shape_regularity'] = 1.0 / (abs(orientation_features.get('aspect_ratio', 1) - 1.0) + 0.1)
            
        elif orientation == 'sagittal':
            # For sagittal: emphasize midline clarity and anteroposterior structures
            metrics['midline_clarity'] = 1.0 - orientation_features.get('vertical_symmetry', 0.5)
            metrics['ap_structures'] = orientation_features.get('intensity_std', 0) / 50.0
            
        elif orientation == 'coronal':
            # For coronal: emphasize bilateral structures and vertical organization
            metrics['bilateral_balance'] = orientation_features.get('horizontal_symmetry', 0)
            metrics['vertical_organization'] = orientation_features.get('vertical_symmetry', 0)
        
        return metrics
    
    def get_noise_regions(self, image):
        """Extract regions likely to contain noise for SNR calculation"""
        h, w = image.shape
        border_width = min(h, w) // 10
        
        # Extract border regions
        top = image[:border_width, :]
        bottom = image[-border_width:, :]
        left = image[:, :border_width]
        right = image[:, -border_width:]
        
        return np.concatenate([top.flatten(), bottom.flatten(), left.flatten(), right.flatten()])
    
    def calculate_composite_score(self, metrics, orientation):
        """
        Calculate orientation-specific composite quality score
        """
        thresholds = self.quality_thresholds[orientation]
        
        # Normalize metrics
        sharpness_norm = min(metrics.get('sharpness_score', 0) / 150, 1.0)
        contrast_norm = min(metrics.get('contrast', 0) / 60, 1.0)
        snr_norm = min(metrics.get('snr', 0) / 10, 1.0)
        
        # Base score
        base_score = (
            thresholds['blur_weight'] * sharpness_norm +
            thresholds['contrast_weight'] * contrast_norm +
            (1 - thresholds['blur_weight'] - thresholds['contrast_weight'] - thresholds['symmetry_weight']) * snr_norm
        )
        
        # Orientation-specific bonuses
        orientation_bonus = 0
        if orientation == 'axial':
            orientation_bonus = thresholds['symmetry_weight'] * (
                metrics.get('bilateral_symmetry', 0) * 0.6 +
                metrics.get('shape_regularity', 0) * 0.4
            )
        elif orientation == 'sagittal':
            orientation_bonus = thresholds['symmetry_weight'] * (
                metrics.get('midline_clarity', 0) * 0.7 +
                min(metrics.get('ap_structures', 0), 1.0) * 0.3
            )
        elif orientation == 'coronal':
            orientation_bonus = thresholds['symmetry_weight'] * (
                metrics.get('bilateral_balance', 0) * 0.5 +
                metrics.get('vertical_organization', 0) * 0.5
            )
        
        final_score = (base_score + orientation_bonus) * 100
        return int(min(final_score, 100))
    
    def get_quality_class(self, score, orientation):
        """Get quality classification based on orientation-specific thresholds"""
        thresholds = self.quality_thresholds[orientation]
        
        if score >= thresholds['excellent']:
            return "EXCELLENT"
        elif score >= thresholds['good']:
            return "GOOD"
        elif score >= thresholds['fair']:
            return "FAIR"
        else:
            return "POOR"
    
    def analyze_dicom_file(self, dicom_path):
        """
        Analyze a single DICOM file with orientation detection
        """
        try:
            ds = pydicom.dcmread(dicom_path, force=True)
            
            if not hasattr(ds, 'pixel_array'):
                return {'error': 'No pixel data found'}
            
            image_array = ds.pixel_array
            
            # Handle multi-frame DICOM
            if len(image_array.shape) > 2:
                mid_frame = image_array.shape[0] // 2
                image_array = image_array[mid_frame]
            
            # Detect fetal brain orientation
            orientation, orientation_confidence, orientation_features = \
                self.orientation_detector.determine_fetal_orientation(image_array)
            
            # Calculate quality metrics
            metrics = self.calculate_orientation_specific_quality(
                image_array, orientation, orientation_features
            )
            
            # Calculate composite score
            composite_score = self.calculate_composite_score(metrics, orientation)
            quality_class = self.get_quality_class(composite_score, orientation)
            
            # Get acquisition plane from DICOM metadata if available
            acquisition_plane = "UNKNOWN"
            if hasattr(ds, 'ImageOrientationPatient'):
                # This would be the mother's acquisition plane
                acquisition_plane = self.get_acquisition_plane_from_metadata(ds)
            
            return {
                'file_path': str(dicom_path),
                'composite_score': composite_score,
                'quality_class': quality_class,
                'fetal_orientation': orientation.upper(),
                'orientation_confidence': round(orientation_confidence, 3),
                'maternal_acquisition_plane': acquisition_plane,
                'sharpness_score': round(metrics.get('sharpness_score', 0), 2),
                'contrast': round(metrics.get('contrast', 0), 2),
                'snr': round(metrics.get('snr', 0), 2),
                'image_shape': image_array.shape,
                'orientation_features': orientation_features
            }
            
        except Exception as e:
            return {
                'file_path': str(dicom_path),
                'error': str(e)
            }
    
    def get_acquisition_plane_from_metadata(self, ds):
        """Extract acquisition plane from DICOM metadata"""
        try:
            if hasattr(ds, 'ImageOrientationPatient'):
                iop = ds.ImageOrientationPatient
                # Simple heuristic based on image orientation
                # This is the mother's acquisition plane
                if abs(iop[0]) > 0.9:  # Sagittal
                    return "SAGITTAL"
                elif abs(iop[1]) > 0.9:  # Coronal  
                    return "CORONAL"
                elif abs(iop[2]) > 0.9:  # Axial
                    return "AXIAL"
            return "UNKNOWN"
        except:
            return "UNKNOWN"
    
    def analyze_patient_folder(self, folder_path):
        """
        Analyze all DICOM files in a patient folder
        """
        folder_path = Path(folder_path)
        dicom_files = list(folder_path.glob("*.dcm")) + list(folder_path.glob("*.DCM"))
        
        if not dicom_files:
            return {'error': 'No DICOM files found'}
        
        results = []
        for dcm_file in dicom_files:
            result = self.analyze_dicom_file(dcm_file)
            if 'error' not in result:
                results.append(result)
        
        if not results:
            return {'error': 'No valid DICOM files processed'}
        
        # Find the best quality image
        best_result = max(results, key=lambda x: x['composite_score'])
        
        # Get orientation distribution
        orientations = [r['fetal_orientation'] for r in results]
        most_common_orientation = max(set(orientations), key=orientations.count)
        
        return {
            'folder_path': str(folder_path),
            'folder_name': folder_path.name,
            'total_dicoms': len(dicom_files),
            'valid_dicoms': len(results),
            'best_score': best_result['composite_score'],
            'best_quality_class': best_result['quality_class'],
            'best_file': best_result['file_path'],
            'fetal_orientation': best_result['fetal_orientation'],
            'orientation_confidence': best_result['orientation_confidence'],
            'maternal_acquisition_plane': best_result['maternal_acquisition_plane'],
            'most_common_fetal_orientation': most_common_orientation,
            'avg_score': round(np.mean([r['composite_score'] for r in results]), 1),
            'all_results': results
        }

def rename_folders_with_scores_and_orientation(master_folder_path, dry_run=True):
    """
    Rename patient folders with quality scores and fetal orientation
    """
    assessor = FetalBrainQualityAssessor()
    master_path = Path(master_folder_path)
    
    if not master_path.exists():
        print(f"Error: Master folder {master_folder_path} does not exist")
        return
    
    results = []
    
    print(f"Analyzing fetal brain folders in: {master_folder_path}")
    print(f"Dry run mode: {dry_run}")
    print("-" * 80)
    
    for patient_folder in master_path.iterdir():
        if patient_folder.is_dir() and not patient_folder.name.startswith('.'):
            print(f"Processing: {patient_folder.name}")
            
            folder_result = assessor.analyze_patient_folder(patient_folder)
            
            if 'error' in folder_result:
                print(f"  ❌ Error: {folder_result['error']}")
                continue
            
            best_score = folder_result['best_score']
            quality_class = folder_result['best_quality_class']
            fetal_orientation = folder_result['fetal_orientation']
            orientation_confidence = folder_result['orientation_confidence']
            maternal_plane = folder_result['maternal_acquisition_plane']
            
            # Create new folder name with score, orientation, and quality
            original_name = patient_folder.name
            
            # Remove existing prefixes if present
            if any(original_name.startswith(prefix) for prefix in 
                   ['EXCELLENT_', 'GOOD_', 'FAIR_', 'POOR_', 'AXIAL_', 'SAGITTAL_', 'CORONAL_']):
                # Find pattern and remove prefix
                parts = original_name.split('_')
                # Remove quality and orientation prefixes
                clean_parts = []
                skip_next = False
                for i, part in enumerate(parts):
                    if skip_next:
                        skip_next = False
                        continue
                    if part.isdigit() or part in ['EXCELLENT', 'GOOD', 'FAIR', 'POOR', 
                                                 'AXIAL', 'SAGITTAL', 'CORONAL']:
                        continue
                    clean_parts.append(part)
                original_name = '_'.join(clean_parts) if clean_parts else original_name
            
            # Create comprehensive new name
            confidence_str = f"C{int(orientation_confidence*100):02d}" if orientation_confidence > 0.5 else "C??"
            
            new_name = f"{best_score:02d}_{quality_class}_{fetal_orientation}_{confidence_str}_{original_name}"
            new_path = patient_folder.parent / new_name
            
            print(f"  📊 Quality Score: {best_score}/100 ({quality_class})")
            print(f"  🧠 Fetal Orientation: {fetal_orientation} (confidence: {orientation_confidence:.2f})")
            print(f"  🤱 Maternal Acquisition: {maternal_plane}")
            print(f"  📁 Current: {patient_folder.name}")
            print(f"  📁 New:     {new_name}")
            
            if not dry_run:
                try:
                    patient_folder.rename(new_path)
                    print(f"  ✅ Renamed successfully")
                except Exception as e:
                    print(f"  ❌ Rename failed: {e}")
            else:
                print(f"  🔍 Dry run - no changes made")
            
            folder_result['original_name'] = patient_folder.name
            folder_result['new_name'] = new_name
            results.append(folder_result)
            print()
    
    # Save detailed results
    if results:
        df = pd.DataFrame(results)
        results_file = master_path / "fetal_brain_orientation_quality_analysis.csv"
        df.to_csv(results_file, index=False)
        print(f"📄 Detailed results saved to: {results_file}")
        
        # Summary statistics
        print("\n📈 SUMMARY STATISTICS:")
        print(f"Total folders processed: {len(results)}")
        print(f"Average quality score: {df['best_score'].mean():.1f}")
        
        print(f"\nQuality distribution:")
        quality_counts = df['best_quality_class'].value_counts()
        for quality, count in quality_counts.items():
            print(f"  {quality}: {count} folders")
        
        print(f"\nFetal orientation distribution:")
        orientation_counts = df['fetal_orientation'].value_counts()
        for orientation, count in orientation_counts.items():
            print(f"  {orientation}: {count} folders")
            
        print(f"\nMaternal acquisition plane distribution:")
        maternal_counts = df['maternal_acquisition_plane'].value_counts()
        for plane, count in maternal_counts.items():
            print(f"  {plane}: {count} folders")
    
    return results

# Example usage
if __name__ == "__main__":
    # Set your master folder path here
    MASTER_FOLDER = "/home/htic/VedantSingh/CASE0030_0003016796 (copy)"
    
    # First run in dry-run mode to see what would happen
    #print("=== DRY RUN MODE ===")
    #results = rename_folders_with_scores_and_orientation(MASTER_FOLDER, dry_run=True)
    
    # Uncomment the line below to actually rename the folders
    print("\n=== ACTUAL RENAMING ===")
    results = rename_folders_with_scores_and_orientation(MASTER_FOLDER, dry_run=False)
